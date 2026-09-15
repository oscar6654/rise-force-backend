class DropProductBasePrice < ActiveRecord::Migration[8.1]
  def up
    # item_cost (per piece) and case_cost (per case) are the cost basis the
    # pricing matrix (tier × store category) marks up. base_price is retired.
    remove_column :products, :base_price
  end

  def down
    add_column :products, :base_price, :decimal, precision: 12, scale: 2, null: false, default: 0
  end
end
