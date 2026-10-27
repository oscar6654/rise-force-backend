module Wms
  # Append-only writer for the stock_movements ledger. Every counter change in
  # the WMS goes through here so the ledger is the one true history (and the
  # future-AI substrate). Never UPDATE/DELETE a movement — append a correction.
  module Ledger
    module_function

    def record!(warehouse:, type:, quantity:, field: :on_hand, lot: nil, location: nil,
                to_location: nil, product: nil, staff: nil, user: nil, receipt: nil,
                fulfillment_order: nil, pick_allocation: nil, cycle_count: nil,
                reason: nil, metadata: {})
      StockMovement.create!(
        warehouse: warehouse, movement_type: type, field: field, quantity: quantity,
        inventory_lot: lot, storage_location: location || lot&.storage_location,
        to_storage_location: to_location, product: product || lot&.product,
        warehouse_staff: staff, user: user, receipt: receipt,
        fulfillment_order: fulfillment_order, pick_allocation: pick_allocation,
        cycle_count: cycle_count, reason: reason, metadata: metadata, occurred_at: Time.current
      )
    end
  end
end
