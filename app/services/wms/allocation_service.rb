module Wms
  # FIFO reservation of stock against a fulfillment order. For each line, consume
  # available lots (pickable locations only — buffer stock is excluded) oldest
  # received_date first, creating pick_allocations and bumping each lot's
  # qty_allocated under a row lock so two concurrent allocations can't over-commit.
  # The specific lot's product IS the resolved itemkey that prints on the pick file.
  # Idempotent: re-running skips lines already allocated.
  class AllocationService
    def initialize(fulfillment_order)
      @fo = fulfillment_order
      @warehouse = fulfillment_order.warehouse
    end

    def allocate!
      ApplicationRecord.transaction do
        # Reprocess pending AND short lines: a short line can be filled on a later
        # run once stock is moved into a pickable bin (buffer → pick) or received.
        @fo.fulfillment_lines.where(status: %i[pending short]).each { |line| allocate_line(line) }
        refresh_order_status!
      end
      @fo
    end

    private

    def allocate_line(line)
      remaining = line.demanded_pieces - line.qty_allocated
      return if remaining <= 0

      lots = lots_for(line)
      lots.each do |lot|
        break if remaining <= 0

        taken = lot.with_lock do
          avail = lot.qty_available
          next 0 if avail <= 0

          take = [avail, remaining].min
          lot.update!(qty_allocated: lot.qty_allocated + take)
          take
        end
        next if taken.to_d <= 0

        PickAllocation.create!(
          fulfillment_line: line, fulfillment_order: @fo, inventory_lot: lot,
          storage_location: lot.storage_location, product: line.product,
          qty_allocated: taken, pack: line.pack, pick_sequence: lot.storage_location&.pick_sequence || 0
        )
        Ledger.record!(warehouse: @warehouse, type: :allocate, quantity: taken, field: :allocated,
                       lot: lot, location: lot.storage_location, product: line.product,
                       fulfillment_order: @fo, reason: "allocate")
        remaining -= taken
      end

      allocated = line.demanded_pieces - remaining
      line.update!(qty_allocated: allocated, status: remaining <= 0 ? :allocated : :short)

      # A loose line that couldn't be filled from the piece zone → raise an auto
      # replenishment task (break the rounded-up cases into pieces).
      raise_replenishment(line, remaining) if remaining.positive? && line.pack_loose? && @warehouse.piece_pick_zone.present?
    end

    # The lot pool for a line: case lines consume case bins, loose lines consume
    # the piece zone. Without a piece zone configured, any pickable bin is used.
    def lots_for(line)
      base = InventoryLot.available.for_product(line.product).where(warehouse: @warehouse)
      zone = @warehouse.piece_pick_zone
      return base.fifo if zone.blank?

      if line.pack_loose?
        base.joins(:storage_location).where("lower(storage_locations.zone) = ?", zone.downcase).fifo
      else
        base.joins(:storage_location).where("storage_locations.zone IS NULL OR lower(storage_locations.zone) <> ?", zone.downcase).fifo
      end
    end

    def raise_replenishment(line, shortfall_pieces)
      return if ReplenishmentTask.open_tasks.exists?(fulfillment_order: @fo, product: line.product)

      c = line.product.pcs_per_case || 1
      cases = (shortfall_pieces / c).ceil
      return if cases <= 0

      ReplenishmentTask.create!(
        warehouse: @warehouse, product: line.product, fulfillment_order: @fo,
        piece_location: piece_location_for(line.product), qty_cases: cases, pieces: cases * c,
        trigger: :auto, status: :pending, notes: "auto — #{shortfall_pieces.to_i} pc short for #{@fo.reference_no}"
      )
    end

    # A piece-zone location to replenish into: one holding this product, else the
    # first pickable piece-zone bin.
    def piece_location_for(product)
      zone = @warehouse.piece_pick_zone
      in_zone = @warehouse.storage_locations.pickable.where("lower(zone) = ?", zone.to_s.downcase)
      in_zone.joins(:inventory_lots).where(inventory_lots: { product_id: product.id }).first ||
        in_zone.by_sequence.first
    end

    def refresh_order_status!
      # Don't downgrade a job already being picked/checked; but a pending OR
      # already-short job can be (re)promoted once lines are (re)allocated.
      return unless @fo.pending? || @fo.short?

      has_short = @fo.fulfillment_lines.pluck(:status).include?("short")
      @fo.update!(status: has_short ? :short : :allocated, allocated_at: @fo.allocated_at || Time.current)
    end
  end
end
