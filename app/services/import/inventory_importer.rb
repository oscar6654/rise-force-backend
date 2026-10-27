module Import
  # Seed / adjust on-hand inventory. One row = one lot at a location.
  # CSV headers: warehouse_code, loc_code, itemkey, it_barcode, lot_code,
  #   received_date, expiry_date, qty_on_hand, uom
  # Never a blind overwrite: the row's target on_hand becomes the lot's on_hand,
  # and the DELTA is written to the ledger as an `adjust` movement.
  class InventoryImporter < BaseImporter
    include WmsHelpers
    JOB_TYPE = :inventory_import
    REPLACE = "replace" # @mode: zero out stock in the file's warehouses that isn't listed

    def initialize(*args, **opts)
      super
      @seen_lot_ids = []       # lots the file set (never zeroed in replace mode)
      @seen_warehouse_ids = [] # warehouses the file touched (replace scope)
    end

    private

    def import_row(row)
      wh = warehouse_for!(row["warehouse_code"])
      loc = wh.storage_locations.find_by("lower(loc_code) = ?", row["loc_code"].to_s.strip.downcase)
      raise "Unknown loc_code '#{row['loc_code']}' in #{wh.whs_code}" unless loc

      product = product_for(sku: row["itemkey"], it_barcode: row["it_barcode"])
      raise "Could not resolve product (itemkey/it_barcode)" unless product

      target = to_pieces(row["qty_on_hand"], row["uom"], product)
      received = parse_date(row["received_date"]) || Date.current

      ApplicationRecord.transaction do
        lot = InventoryLot.find_or_create_by!(
          warehouse: wh, storage_location: loc, product: product,
          lot_code: row["lot_code"].presence, received_date: received
        ) { |l| l.status = :active }
        lot.expiry_date = parse_date(row["expiry_date"]) if row.key?("expiry_date")
        delta = target - lot.qty_on_hand
        lot.with_lock do
          lot.update!(qty_on_hand: [target, lot.qty_allocated + lot.qty_locked].max, status: :active)
        end
        @seen_lot_ids << lot.id
        @seen_warehouse_ids |= [wh.id]
        next if delta.zero?

        Wms::Ledger.record!(warehouse: wh, type: :adjust, quantity: delta, field: :on_hand,
                            lot: lot, location: loc, product: product, user: @user,
                            reason: "inventory upload")
      end
    end

    # Replace / refresh mode: after the listed lots are set, zero out every other
    # active lot that still has free on-hand stock in the warehouses the file
    # touched — a full snapshot overwrite. Reserved stock (allocated/locked) is
    # left alone (we only drop the free portion); each change is a ledger adjust.
    def after_rows(_log)
      return unless @mode == REPLACE
      return if @seen_warehouse_ids.empty?

      stale = InventoryLot.active.where(warehouse_id: @seen_warehouse_ids)
                          .where("qty_on_hand > qty_allocated + qty_locked")
                          .where.not(id: @seen_lot_ids)
      stale.find_each do |lot|
        lot.with_lock do
          floor = lot.qty_allocated + lot.qty_locked
          delta = floor - lot.qty_on_hand # negative (or zero)
          next if delta.zero?

          lot.update!(qty_on_hand: floor)
          Wms::Ledger.record!(warehouse: lot.warehouse, type: :adjust, quantity: delta,
                              field: :on_hand, lot: lot, user: @user,
                              reason: "inventory refresh (not in file)")
        end
      end
    end

    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
