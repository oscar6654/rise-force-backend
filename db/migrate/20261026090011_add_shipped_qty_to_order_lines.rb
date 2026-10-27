class AddShippedQtyToOrderLines < ActiveRecord::Migration[8.1]
  def change
    # For WMS orders, the authoritative shipped qty (net of short picks) comes
    # back from the fulfillment line at dispatch-confirm; the OSB batch CSV emits
    # it when present. Null for non-WMS orders (unchanged behaviour).
    add_column :order_lines, :shipped_qty, :decimal, precision: 14, scale: 2
  end
end
