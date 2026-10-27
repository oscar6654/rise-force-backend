class AddOccurredAtIndexToStockMovements < ActiveRecord::Migration[8.1]
  # The stock ledger (audit trail) orders globally by occurred_at and the CSV
  # export filters on an occurred_at window. The only existing index is the
  # composite [warehouse_id, occurred_at], which Postgres can't use for an
  # all-warehouse ORDER BY / range scan — so a large ledger would do a full
  # sort. A plain occurred_at index keeps both fast.
  def change
    add_index :stock_movements, :occurred_at, name: "index_stock_movements_on_occurred_at"
  end
end
