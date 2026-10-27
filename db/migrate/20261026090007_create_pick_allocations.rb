class CreatePickAllocations < ActiveRecord::Migration[8.1]
  def change
    create_table :pick_allocations do |t|
      t.references :fulfillment_line, null: false, foreign_key: true
      t.references :fulfillment_order, null: false, foreign_key: true # denormalized for routing
      t.references :inventory_lot, null: true, foreign_key: true
      t.references :storage_location, null: true, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.decimal :qty_allocated, precision: 14, scale: 2, default: "0.0", null: false
      t.decimal :qty_picked,    precision: 14, scale: 2, default: "0.0", null: false
      # allocated=0, locked=1, picked=2, partial=3, short=4, cancelled=5
      t.integer :status, default: 0, null: false
      t.integer :pick_sequence, default: 0, null: false

      t.timestamps
    end
  end
end
