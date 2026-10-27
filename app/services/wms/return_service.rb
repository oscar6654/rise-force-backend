module Wms
  # Record a return and its disposition (FMCG returns & quality):
  #   saleable   → stock goes back to a saleable lot at a pick/buffer location.
  #   damaged    → stock lands in a damage location as a damaged lot (writeoff).
  #   quarantine → QA hold: a quarantine lot (not pickable until released).
  # Each writes the matching ledger movement. Quantities are in pieces.
  class ReturnService
    class Error < StandardError; end

    def initialize(warehouse, user: nil, staff: nil)
      @warehouse = warehouse
      @user = user
      @staff = staff
    end

    # Suggest where to drop a returned line based on its disposition:
    #   damaged / quarantine → the damage zone (not pickable);
    #   saleable → back into sellable stock — the piece zone for a loose return,
    #     else a putaway-style accepting pick slot (nearest, free).
    def self.suggest_location(warehouse, product, disposition, loose: false)
      case disposition.to_s
      when "damaged", "quarantine"
        warehouse.storage_locations.where(loc_type: :damage, status: :active).order(:pick_sequence, :loc_code).first
      else
        if loose && warehouse.piece_pick_zone.present?
          warehouse.storage_locations.pickable.where("lower(zone) = ?", warehouse.piece_pick_zone.downcase)
                   .select { |l| l.accepts?(product) && l.has_free_slot? }.min_by(&:pick_sequence)
        else
          Wms::PutawayService.new(InventoryLot.new(warehouse: warehouse, product: product)).suggest
        end
      end
    end

    # disposition: "saleable" | "damaged" | "quarantine"
    def record!(product:, qty:, disposition:, location:, reason: nil)
      qty = qty.to_d
      raise Error, "Qty must be positive" if qty <= 0
      raise Error, "Location is in another warehouse" unless location.warehouse_id == @warehouse.id

      status, type = case disposition.to_s
                     when "saleable"   then [:active, :return_in]
                     when "damaged"    then [:damaged, :damage]
                     when "quarantine" then [:quarantine, :quarantine]
                     else raise Error, "Unknown disposition '#{disposition}'"
                     end

      ApplicationRecord.transaction do
        lot = InventoryLot.find_or_create_by!(
          warehouse: @warehouse, storage_location: location, product: product,
          lot_code: "RET-#{Date.current.iso8601}", received_date: Date.current
        ) { |l| l.status = status }
        lot.with_lock { lot.update!(qty_on_hand: lot.qty_on_hand + qty, status: status) }
        Ledger.record!(warehouse: @warehouse, type: type, quantity: qty, field: :on_hand,
                       lot: lot, location: location, product: product, user: @user,
                       reason: reason || "return (#{disposition})")
        lot
      end
    end
  end
end
