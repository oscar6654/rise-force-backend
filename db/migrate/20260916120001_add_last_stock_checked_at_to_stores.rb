class AddLastStockCheckedAtToStores < ActiveRecord::Migration[8.1]
  def change
    add_column :stores, :last_stock_checked_at, :datetime
  end
end
