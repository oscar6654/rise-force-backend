module Wms
  # Self-heal lot counter drift: recompute qty_allocated / qty_locked from the
  # open pick_allocations that actually reference each lot, so a crashed pick or
  # a half-applied transaction can't leave stock stuck as reserved. on_hand is
  # NOT touched here (that is the cycle-count's job); only the reservation
  # counters are rebuilt from the allocation truth.
  class ReconcileCountersJob < ApplicationJob
    queue_as :default

    def perform(warehouse_id = nil)
      scope = InventoryLot.all
      scope = scope.where(warehouse_id: warehouse_id) if warehouse_id

      scope.find_each do |lot|
        allocated = PickAllocation.where(inventory_lot_id: lot.id, status: :allocated).sum(:qty_allocated)
        locked    = PickAllocation.where(inventory_lot_id: lot.id, status: :locked).sum(:qty_allocated)
        next if lot.qty_allocated == allocated && lot.qty_locked == locked

        lot.with_lock do
          # Clamp the SUM to on_hand (locked first, then allocated with the room
          # that's left) so the rebuilt counters never violate the DB check
          # constraint on_hand >= allocated + locked.
          on_hand = lot.qty_on_hand
          new_locked = [locked, on_hand].min
          new_allocated = [allocated, on_hand - new_locked].min
          lot.update_columns(qty_allocated: new_allocated, qty_locked: new_locked)
        end
      end
    end
  end
end
