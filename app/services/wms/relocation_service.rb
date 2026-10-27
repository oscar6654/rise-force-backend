module Wms
  # Manual stock movement between locations: buffer → pick slot (makes stock
  # pickable), consolidating, emptying a slot, or reclassing to a damage location.
  # Frees the source slot once it hits zero. Writes a paired `relocate` movement.
  class RelocationService
    class Error < StandardError; end

    def initialize(lot, staff: nil, user: nil)
      @lot = lot
      @warehouse = lot.warehouse
      @staff = staff
      @user = user
    end

    def move!(to_location:, qty: nil)
      raise Error, "Destination is in another warehouse" unless to_location.warehouse_id == @warehouse.id

      qty = @lot.qty_on_hand if qty.nil?
      qty = qty.to_d
      raise Error, "Move qty must be positive and within the lot" if qty <= 0 || qty > @lot.qty_on_hand

      from = @lot.storage_location
      unless to_location == from
        raise Error, "#{to_location.loc_code} does not accept this SKU" unless to_location.accepts?(@lot.product)
        raise Error, "#{to_location.loc_code} has no free slot" unless to_location.has_free_slot?
      end

      ApplicationRecord.transaction do
        dest =
          if qty == @lot.qty_on_hand
            @lot.with_lock { @lot.update!(storage_location: to_location) }
            @lot
          else
            split_into(to_location, qty)
          end
        Ledger.record!(warehouse: @warehouse, type: :relocate, quantity: qty, field: :on_hand,
                       lot: dest, location: from, to_location: to_location, product: @lot.product,
                       staff: @staff, user: @user, reason: "relocate")
        dest
      end
    end

    private

    def split_into(to_location, qty)
      dest = InventoryLot.find_or_create_by!(
        warehouse: @warehouse, storage_location: to_location, product: @lot.product,
        lot_code: @lot.lot_code, received_date: @lot.received_date
      ) { |l| l.status = :active }
      @lot.with_lock { @lot.update!(qty_on_hand: @lot.qty_on_hand - qty) }
      dest.with_lock { dest.update!(qty_on_hand: dest.qty_on_hand + qty, status: :active) }
      dest
    end
  end
end
