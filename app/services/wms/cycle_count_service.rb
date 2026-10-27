module Wms
  # Cycle counting for Inventory Record Accuracy (IRA). A count is opened against
  # a location (scheduled/random/manual/pick_discrepancy), the system qty is
  # snapshotted but hidden from the counter (blind count), the counter submits a
  # physical figure, and a console user reconciles — writing an `adjust` movement
  # that sets on_hand to the counted qty and clearing the location's flag.
  class CycleCountService
    class Error < StandardError; end

    # Open a pending count. Snapshots the current system qty for the location
    # (optionally for one product/lot). Idempotent-ish: skips if an open count
    # already exists for the location.
    def self.open!(storage_location, trigger: :manual, product: nil, inventory_lot: nil, reason: nil)
      existing = CycleCount.open_counts.find_by(storage_location: storage_location, product: product)
      return existing if existing

      system_qty = scoped_lots(storage_location, product, inventory_lot).sum(:qty_on_hand)
      CycleCount.create!(
        warehouse: storage_location.warehouse, storage_location: storage_location, product: product,
        inventory_lot: inventory_lot, trigger: trigger, status: :pending, system_qty: system_qty, reason: reason
      )
    end

    def initialize(cycle_count)
      @count = cycle_count
    end

    # Counter submits the physical figure (blind — they never saw system_qty).
    def submit!(counted_qty:, staff: nil)
      counted = counted_qty.to_d
      @count.update!(counted_qty: counted, variance: counted - @count.system_qty.to_d,
                     counted_by: staff, counted_at: Time.current, status: :counted)
      @count
    end

    # Console user reconciles: set on_hand to the counted qty via an `adjust`
    # movement, clear the location flag, stamp last_counted_at.
    def reconcile!(user:)
      raise Error, "Count must be submitted before reconcile" unless @count.counted?

      ApplicationRecord.transaction do
        apply_adjustment!(user)
        @count.storage_location.update!(needs_cycle_count: false, last_counted_at: Time.current)
        @count.update!(status: :reconciled, reconciled_by: user, reconciled_at: Time.current)
      end
      @count
    end

    def self.scoped_lots(location, product, lot)
      scope = location.inventory_lots
      scope = scope.where(product: product) if product
      scope = scope.where(id: lot.id) if lot
      scope
    end

    private

    # Drive on-hand to the counted figure. With a single lot in scope we set it
    # directly; with several we adjust the newest lot by the net variance (a
    # pragmatic default — a per-lot blind count can refine this later).
    def apply_adjustment!(user)
      delta = @count.variance.to_d
      return if delta.zero?

      lots = self.class.scoped_lots(@count.storage_location, @count.product, @count.inventory_lot)
      target = @count.inventory_lot || lots.order(received_date: :desc, id: :desc).first
      return unless target

      target.with_lock do
        new_on_hand = [target.qty_on_hand + delta, target.qty_allocated + target.qty_locked].max
        new_on_hand = 0 if new_on_hand.negative?
        target.update!(qty_on_hand: new_on_hand)
      end
      Ledger.record!(warehouse: @count.warehouse, type: :adjust, quantity: delta, field: :on_hand,
                     lot: target, location: @count.storage_location, product: target.product,
                     cycle_count: @count, user: user, reason: "cycle count reconcile (IRA)")
    end
  end
end
