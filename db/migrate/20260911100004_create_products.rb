class CreateProducts < ActiveRecord::Migration[8.1]
  def change
    create_table :products do |t|
      t.references :brand, foreign_key: true, null: true
      t.references :product_category, foreign_key: true, null: true
      t.string  :sku, null: false
      t.string  :description, null: false
      t.integer :tier, null: false, default: 2            # 1 premium, 2 mainstream, 3 value
      t.integer :must_stock_type                          # distribution/initiative/focus/npd
      t.string  :case_uom
      t.string  :pc_uom
      t.integer :pcs_per_case
      t.decimal :base_price, precision: 12, scale: 2, null: false, default: 0
      t.integer :status, null: false, default: 0
      t.string  :vcsi_product_ref

      t.timestamps
    end
    add_index :products, :sku, unique: true
    add_index :products, :vcsi_product_ref
    add_index :products, [:tier, :status]
  end
end
