class AddStoreAndCountedOnToStockCounts < ActiveRecord::Migration[8.1]
  def change
    # Diser (and any future) counts can be store-scoped with no visit, so they
    # never touch coverage/productive-call metrics. counted_on = the device date
    # the shelf was actually counted (offline-safe), independent of sync time.
    add_column :stock_counts, :store_id, :bigint
    add_column :stock_counts, :counted_on, :date
    add_index :stock_counts, :store_id
    change_column_null :stock_counts, :visit_id, true
  end
end
