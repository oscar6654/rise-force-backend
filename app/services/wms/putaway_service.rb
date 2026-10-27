module Wms
  # Decide where a received lot goes, and move it there. Candidates are empty
  # (or mixed-lot-capable) locations that ACCEPT the SKU (allowed_abc_classes /
  # allowed_brand_ids), ordered nearest-first by pick_sequence; high-value brands
  # go to secured high-value shelves; overflow spills to the non-pickable buffer.
  class PutawayService
    class Error < StandardError; end

    # Destination preference by location type (lower = tried first). Buffer is
    # last (and not pickable — stock there must be relocated before it can ship).
    TYPE_ORDER = { "pick_rack" => 0, "bulk" => 1, "high_value" => 2, "staging" => 3, "buffer" => 4 }.freeze
    DESTINATION_TYPES = %w[pick_rack bulk high_value buffer].freeze

    def initialize(lot, staff: nil)
      @lot = lot
      @warehouse = lot.warehouse
      @product = lot.product
      @staff = staff
    end

    # Best suggested destination (or nil if the warehouse is full).
    def suggest
      candidates.first
    end

    # All acceptable destinations, best first (for the app's override picker).
    def candidates
      high_value = @product.brand&.high_value
      @warehouse.storage_locations
                .where(status: StorageLocation.statuses[:active], loc_type: destination_loc_types(high_value))
                .select { |l| l.accepts?(@product) && l.has_free_slot? }
                .sort_by { |l| [TYPE_ORDER[l.loc_type] || 9, l.pick_sequence, l.loc_code] }
    end

    # Move `qty` pieces of the lot into `location`. Moving the whole lot relocates
    # it; a partial putaway splits off a new lot at the destination. Writes a
    # `putaway` movement. Override = any active destination location passed in.
    def putaway!(location:, qty: nil)
      raise Error, "Location is in another warehouse" unless location.warehouse_id == @warehouse.id
      raise Error, "#{location.loc_code} does not accept this SKU" unless location.accepts?(@product)
      raise Error, "#{location.loc_code} has no free slot" unless location.has_free_slot? || location == @lot.storage_location

      qty = @lot.qty_on_hand if qty.nil?
      qty = qty.to_d
      raise Error, "Putaway qty must be positive and within the lot" if qty <= 0 || qty > @lot.qty_on_hand

      ApplicationRecord.transaction do
        dest_lot =
          if qty == @lot.qty_on_hand
            @lot.with_lock { @lot.update!(storage_location: location, status: :active) }
            @lot
          else
            split_into(location, qty)
          end
        Ledger.record!(warehouse: @warehouse, type: :putaway, quantity: qty, field: :on_hand,
                       lot: dest_lot, location: location, to_location: location, product: @product,
                       staff: @staff, reason: "putaway",
                       metadata: { from_location: @lot.storage_location_id })
        dest_lot
      end
    end

    private

    def destination_loc_types(high_value)
      high_value ? %w[high_value] : (DESTINATION_TYPES - %w[high_value])
    end

    # Partial putaway: reduce the source (dock) lot and create/augment a lot at
    # the destination, keeping received_date so FIFO is preserved.
    def split_into(location, qty)
      dest = InventoryLot.find_or_create_by!(
        warehouse: @warehouse, storage_location: location, product: @product,
        lot_code: @lot.lot_code, received_date: @lot.received_date
      ) { |l| l.status = :active }
      @lot.with_lock do
        @lot.update!(qty_on_hand: @lot.qty_on_hand - qty)
      end
      dest.with_lock { dest.update!(qty_on_hand: dest.qty_on_hand + qty, status: :active) }
      dest
    end
  end
end
