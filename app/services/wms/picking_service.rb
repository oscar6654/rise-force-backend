module Wms
  # Picker lifecycle for a fulfillment order's allocations.
  #   start! — picker begins: lock every open allocation (allocated → locked).
  #   confirm! — scan location + item, record what was physically picked
  #     (locked → on_hand−). A short pick releases the remaining reservation,
  #     flags the location for a cycle count, and re-sources the shortfall from
  #     another FIFO location (Wms::PickShortService).
  class PickingService
    class Error < StandardError; end

    def initialize(staff: nil)
      @staff = staff
    end

    # Lock all open allocations for a job and move it into picking.
    def start!(fulfillment_order)
      ApplicationRecord.transaction do
        fulfillment_order.pick_allocations.where(status: :allocated).each { |a| lock!(a) }
        fulfillment_order.update!(status: :picking) unless fulfillment_order.picking?
      end
      fulfillment_order
    end

    def lock!(allocation)
      lot = allocation.inventory_lot
      lot.with_lock do
        lot.update!(qty_allocated: [lot.qty_allocated - allocation.qty_allocated, 0].max,
                    qty_locked: lot.qty_locked + allocation.qty_allocated)
      end
      allocation.update!(status: :locked)
      Ledger.record!(warehouse: lot.warehouse, type: :lock, quantity: allocation.qty_allocated,
                     field: :locked, lot: lot, location: lot.storage_location, product: allocation.product,
                     fulfillment_order: allocation.fulfillment_order, pick_allocation: allocation, staff: @staff)
    end

    # Confirm a physical pick against one allocation. `location_code` and
    # `barcode` must match the allocation's location and product (strict).
    # On a short (qty_picked < qty_allocated), `on_short`:
    #   :resource — re-source the shortfall from another FIFO bin (default)
    #   :close    — can't find it anywhere: flag the bin for IRA, leave line short
    #   :none     — just record the partial (no re-source, no flag)
    def confirm!(allocation, qty_picked:, barcode: nil, location_code: nil, on_short: :resource, find_elsewhere: nil)
      on_short = find_elsewhere == false ? :none : on_short unless find_elsewhere.nil? # back-compat
      raise Error, "Allocation already closed" unless allocation.allocated? || allocation.locked?

      lot = allocation.inventory_lot
      validate_scan!(allocation, barcode, location_code)
      qty_picked = qty_picked.to_d
      raise Error, "Picked qty cannot exceed the allocated qty" if qty_picked > allocation.qty_allocated
      # 0 is allowed only when closing short (found nothing at this bin).
      raise Error, "Picked qty must be positive" if qty_picked <= 0 && on_short != :close

      ApplicationRecord.transaction do
        allocation = PickAllocation.lock.find(allocation.id)
        lock!(allocation) if allocation.allocated? # auto-lock if start! was skipped

        lot.with_lock do
          lot.update!(qty_locked: [lot.qty_locked - allocation.qty_allocated, 0].max,
                      qty_on_hand: [lot.qty_on_hand - qty_picked, 0].max)
        end
        if qty_picked.positive?
          Ledger.record!(warehouse: lot.warehouse, type: :pick, quantity: qty_picked, field: :on_hand,
                         lot: lot, location: lot.storage_location, product: allocation.product,
                         fulfillment_order: allocation.fulfillment_order, pick_allocation: allocation, staff: @staff)
        end

        shortfall = allocation.qty_allocated - qty_picked
        # :close marks the allocation short (gave up); :resource/:none leave it partial.
        final = shortfall.zero? ? :picked : (on_short == :close ? :short : :partial)
        allocation.update!(qty_picked: qty_picked, status: final)
        bump_line_picked(allocation.fulfillment_line, qty_picked)

        if shortfall.positive?
          case on_short
          when :resource then PickShortService.new(allocation, shortfall, staff: @staff).resource!
          when :close    then PickShortService.new(allocation, shortfall, staff: @staff).close!
          end
        end
        advance_order!(allocation.fulfillment_order)
      end
      allocation
    end

    # Job-level "finish short": the picker gives up on everything still open.
    # Release each open allocation's reservation back to stock, flag its bin for
    # a cycle count (IRA), mark it short, and close the job to checking.
    def finish_short!(fulfillment_order)
      ApplicationRecord.transaction do
        fulfillment_order.pick_allocations.where(status: %i[allocated locked]).each do |a|
          lot = a.inventory_lot
          lot&.with_lock do
            if a.locked?
              lot.update!(qty_locked: [lot.qty_locked - a.qty_allocated, 0].max)
            else
              lot.update!(qty_allocated: [lot.qty_allocated - a.qty_allocated, 0].max)
            end
          end
          if a.storage_location
            a.storage_location.update!(needs_cycle_count: true)
            Wms::CycleCountService.open!(a.storage_location, trigger: :pick_discrepancy, product: a.product,
                                         inventory_lot: a.inventory_lot, reason: "finish short — not found")
          end
          Ledger.record!(warehouse: fulfillment_order.warehouse, type: :short, quantity: a.qty_outstanding,
                         field: :allocated, lot: lot, location: a.storage_location, product: a.product,
                         fulfillment_order: fulfillment_order, pick_allocation: a, staff: @staff, reason: "finish short")
          a.update!(status: :short)
        end
        advance_order!(fulfillment_order)
      end
      fulfillment_order
    end

    # Undo a completed pick line (picked/partial/short) — return it to the pick
    # list: put the physically-picked qty back on hand, re-reserve the allocation,
    # reset it to `allocated`, and move the job back to picking.
    def undo!(allocation)
      # Only a FULLY picked allocation can be undone cleanly: a partial/short one
      # has already had its shortfall re-sourced to a sibling allocation, so
      # reversing it would double-reserve. (Re-allocate the job to redo those.)
      raise Error, "Only a fully-picked line can be undone (re-allocate for a short line)" unless allocation.picked?

      ApplicationRecord.transaction do
        alloc = PickAllocation.lock.find(allocation.id)
        returned = alloc.qty_picked
        lot = alloc.inventory_lot
        lot&.with_lock do
          lot.update!(qty_on_hand: lot.qty_on_hand + returned, qty_allocated: lot.qty_allocated + alloc.qty_allocated)
        end
        if returned.positive?
          Ledger.record!(warehouse: alloc.fulfillment_order.warehouse, type: :adjust, quantity: returned, field: :on_hand,
                         lot: lot, location: alloc.storage_location, product: alloc.product,
                         fulfillment_order: alloc.fulfillment_order, pick_allocation: alloc, staff: @staff,
                         reason: "undo pick (returned to pick list)")
        end
        line = alloc.fulfillment_line
        line.update!(qty_picked: [line.qty_picked - returned, 0].max, status: :allocated)
        alloc.update!(qty_picked: 0, status: :allocated)
        fo = alloc.fulfillment_order
        fo.update!(status: :picking) if fo.picked? || fo.short? || fo.checking?
      end
      allocation.reload
    rescue ActiveRecord::StatementInvalid => e
      raise Error, "Can't undo — this stock has been re-allocated. Re-allocate the job instead. (#{e.message.lines.first&.strip})"
    end

    private

    def validate_scan!(allocation, barcode, location_code)
      loc = allocation.storage_location
      if location_code.present? && loc && !location_code.to_s.casecmp?(loc.loc_code)
        raise Error, "Scanned location #{location_code} is not #{loc.loc_code}"
      end
      if barcode.present? && allocation.product.it_barcode.present? && barcode.to_s.strip != allocation.product.it_barcode
        raise Error, "Scanned item does not match the allocated SKU"
      end
    end

    def bump_line_picked(line, qty)
      line.update!(qty_picked: line.qty_picked + qty)
    end

    # Once every allocation of a job is resolved (picked/partial/short/cancelled),
    # move it to picked (or short) ready for checking.
    def advance_order!(fo)
      open = fo.pick_allocations.where(status: %i[allocated locked]).exists?
      return if open

      any_short = fo.fulfillment_lines.where("qty_picked < qty_demanded").exists?
      fo.update!(status: any_short ? :short : :picked, picked_at: Time.current)
    end
  end
end
