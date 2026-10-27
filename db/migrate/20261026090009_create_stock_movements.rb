class CreateStockMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :stock_movements do |t|
      t.references :warehouse, null: false, foreign_key: true
      t.references :inventory_lot, null: true, foreign_key: true
      t.references :storage_location, null: true, foreign_key: true
      t.bigint  :to_storage_location_id # for relocate (move between locations)
      t.references :product, null: true, foreign_key: true
      # receipt=0, putaway=1, relocate=2, allocate=3, deallocate=4, lock=5,
      # unlock=6, pick=7, check=8, short=9, adjust=10, return_in=11, damage=12,
      # quarantine=13, release=14, writeoff=15
      t.integer :movement_type, null: false
      t.decimal :quantity, precision: 14, scale: 2, default: "0.0", null: false # signed
      t.integer :field, default: 0, null: false # on_hand=0, allocated=1, locked=2
      t.references :receipt, null: true, foreign_key: true
      t.references :fulfillment_order, null: true, foreign_key: true
      t.references :pick_allocation, null: true, foreign_key: true
      t.references :cycle_count, null: true, foreign_key: true
      t.bigint  :warehouse_staff_id
      t.bigint  :user_id
      t.string  :reason
      t.jsonb   :metadata, default: {}, null: false
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :stock_movements, %i[warehouse_id occurred_at]
    add_index :stock_movements, :to_storage_location_id
    add_index :stock_movements, :warehouse_staff_id
  end
end
