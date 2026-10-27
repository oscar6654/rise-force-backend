module Wms
  # A pick came up short at its allocated location. Flag that location for a
  # cycle count (IRA), then re-source the shortfall from OTHER pickable FIFO
  # locations by creating a fresh allocation on the same line/job. If nothing
  # else has the stock, the line simply stays short.
  class PickShortService
    def initialize(short_allocation, shortfall_pieces, staff: nil)
      @alloc = short_allocation
      @line = short_allocation.fulfillment_line
      @fo = short_allocation.fulfillment_order
      @warehouse = @fo.warehouse
      @product = short_allocation.product
      @shortfall = shortfall_pieces.to_d
      @staff = staff
    end

    # "Can't find it anywhere" — close the shortfall WITHOUT re-sourcing. Just
    # flag the bin for a cycle count (IRA); the line stays short.
    def close!
      flag_cycle_count!
      []
    end

    # Returns the new pick_allocations created to cover the shortfall (may be []).
    def resource!
      flag_cycle_count!
      created = []
      remaining = @shortfall
      candidate_lots.each do |lot|
        break if remaining <= 0

        taken = lot.with_lock do
          avail = lot.qty_available
          next 0 if avail <= 0

          take = [avail, remaining].min
          lot.update!(qty_allocated: lot.qty_allocated + take)
          take
        end
        next if taken.to_d <= 0

        alloc = PickAllocation.create!(
          fulfillment_line: @line, fulfillment_order: @fo, inventory_lot: lot,
          storage_location: lot.storage_location, product: @product, pack: @line.pack,
          qty_allocated: taken, pick_sequence: lot.storage_location&.pick_sequence || 0
        )
        Ledger.record!(warehouse: @warehouse, type: :allocate, quantity: taken, field: :allocated,
                       lot: lot, location: lot.storage_location, product: @product,
                       fulfillment_order: @fo, pick_allocation: alloc, reason: "re-source after short")
        created << alloc
        remaining -= taken
      end
      created
    end

    private

    # Other sellable lots for the product in the SAME pack zone (a loose shortfall
    # re-sources from the piece zone, a case shortfall from case bins) — excluding
    # the location that came up short.
    def candidate_lots
      scope = InventoryLot.available.for_product(@product).where(warehouse: @warehouse)
      zone = @warehouse.piece_pick_zone
      if zone.present?
        scope = if @line.pack_loose?
                  scope.joins(:storage_location).where("lower(storage_locations.zone) = ?", zone.downcase)
                else
                  scope.joins(:storage_location).where("storage_locations.zone IS NULL OR lower(storage_locations.zone) <> ?", zone.downcase)
                end
      end
      scope = scope.where.not(storage_location_id: @alloc.storage_location_id) if @alloc.storage_location_id
      scope.fifo
    end

    def flag_cycle_count!
      loc = @alloc.storage_location
      return unless loc

      loc.update!(needs_cycle_count: true)
      # Open via the service so the current system qty is snapshotted (blind) —
      # otherwise the later IRA variance has nothing to compare against.
      Wms::CycleCountService.open!(
        loc, trigger: :pick_discrepancy, product: @product, inventory_lot: @alloc.inventory_lot,
        reason: "short pick: expected #{@alloc.qty_allocated.to_i}, picked #{@alloc.qty_picked.to_i}"
      )
    end
  end
end
