module Wms
  # Break full cases from a case bin into loose pieces in the piece-pick zone.
  # Auto tasks are raised by AllocationService when the piece zone runs short;
  # a `replenish`-role worker executes them (or does a manual drop). After a
  # drop, any loose demand that was waiting is re-allocated.
  class ReplenishmentService
    class Error < StandardError; end

    def initialize(warehouse, staff: nil, user: nil)
      @warehouse = warehouse
      @staff = staff
      @user = user
    end

    # Execute a pending replenishment task.
    def execute!(task, from_location: nil)
      pieces = replenish!(task.product, task.qty_cases, from_location: from_location, piece_location: task.piece_location)
      task.update!(status: :done, done_at: Time.current, assigned_to: @staff)
      pieces
    end

    # Manual: pick `qty_cases` of a product from a case bin → drop into the piece
    # zone. Returns the pieces moved.
    def manual!(product:, qty_cases:, from_location: nil, piece_location: nil)
      replenish!(product, qty_cases, from_location: from_location, piece_location: piece_location)
    end

    private

    def replenish!(product, qty_cases, from_location:, piece_location:)
      c = product.pcs_per_case || 1
      pieces = (qty_cases.to_i * c).to_d
      raise Error, "Qty (cases) must be positive" if pieces <= 0

      dest = piece_location || default_piece_location(product)
      raise Error, "No piece-pick location configured (set the warehouse's piece_pick_zone)" unless dest
      # The destination MUST be a loose/piece location — can't drop loose stock
      # into a case bin.
      raise Error, "#{dest.loc_code} is not a loose/piece location" unless dest.piece_pick?

      sources = case_lots(product, from_location)
      available = sources.sum(&:qty_available)
      raise Error, "Not enough full-case stock to break #{qty_cases} case(s) (#{pieces.to_i} pc; have #{available.to_i})" if available < pieces

      # Draw the pieces across one or more FIFO case lots.
      remaining = pieces
      sources.each do |lot|
        break if remaining <= 0

        take = [lot.qty_available, remaining].min
        next if take <= 0

        Wms::RelocationService.new(lot, staff: @staff, user: @user).move!(to_location: dest, qty: take)
        remaining -= take
      end
      reallocate_waiting(product)
      pieces
    end

    public

    # FIFO case lots to pull from for a given piece target — so the app can guide
    # the worker to the right bin(s). Returns [{loc_code, lot_code, available}].
    def fifo_sources(product, pieces)
      remaining = pieces.to_d
      case_lots(product, nil).filter_map do |lot|
        break if remaining <= 0

        take = [lot.qty_available, remaining].min
        next if take <= 0

        remaining -= take
        { loc_code: lot.storage_location&.loc_code, lot_code: lot.lot_code, take: take, available: lot.qty_available }
      end
    end

    private

    # Case-zone lots to break from (FIFO), oldest first.
    def case_lots(product, from_location)
      scope = InventoryLot.available.for_product(product).where(warehouse: @warehouse)
      if from_location
        scope = scope.where(storage_location: from_location)
      elsif @warehouse.piece_pick_zone.present?
        scope = scope.joins(:storage_location)
                     .where("storage_locations.zone IS NULL OR lower(storage_locations.zone) <> ?", @warehouse.piece_pick_zone.downcase)
      end
      scope.fifo.to_a
    end

    def default_piece_location(product)
      zone = @warehouse.piece_pick_zone
      return nil if zone.blank?

      in_zone = @warehouse.storage_locations.pickable.where("lower(zone) = ?", zone.downcase)
      in_zone.joins(:inventory_lots).where(inventory_lots: { product_id: product.id }).first ||
        in_zone.select { |l| l.accepts?(product) }.min_by(&:pick_sequence) ||
        in_zone.by_sequence.first
    end

    # Re-allocate loose demand that was short for this product (now there's stock).
    def reallocate_waiting(product)
      FulfillmentOrder.where(warehouse: @warehouse).open_jobs
                      .joins(:fulfillment_lines)
                      .where(fulfillment_lines: { product_id: product.id,
                                                  pack: FulfillmentLine.packs[:loose],
                                                  status: FulfillmentLine.statuses[:short] })
                      .distinct.each { |fo| Wms::AllocationService.new(fo).allocate! }
    end
  end
end
