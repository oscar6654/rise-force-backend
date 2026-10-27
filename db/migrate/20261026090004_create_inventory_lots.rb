class CreateInventoryLots < ActiveRecord::Migration[8.1]
  def change
    create_table :inventory_lots do |t|
      t.references :warehouse, null: false, foreign_key: true
      t.references :storage_location, null: true, foreign_key: true # null until putaway
      t.references :product, null: false, foreign_key: true
      t.string  :lot_code
      t.date    :received_date, null: false # FIFO key
      t.date    :expiry_date                # captured now; FEFO is a later toggle
      t.decimal :qty_on_hand,   precision: 14, scale: 2, default: "0.0", null: false
      t.decimal :qty_allocated, precision: 14, scale: 2, default: "0.0", null: false
      t.decimal :qty_locked,    precision: 14, scale: 2, default: "0.0", null: false
      t.integer :status, default: 0, null: false # received=0, active=1, quarantine=2, damaged=3, expired=4
      t.integer :lock_version, default: 0, null: false

      t.timestamps
    end

    add_index :inventory_lots,
              %i[warehouse_id product_id storage_location_id lot_code received_date],
              unique: true, name: "index_inventory_lots_identity"
    # FIFO scan over sellable stock.
    add_index :inventory_lots, %i[warehouse_id product_id received_date],
              where: "status = 1", name: "index_inventory_lots_fifo_active"

    # On-hand must cover what's committed, and no counter goes negative.
    add_check_constraint :inventory_lots,
                         "qty_allocated >= 0 AND qty_locked >= 0 AND qty_on_hand >= qty_allocated + qty_locked",
                         name: "inventory_lots_counters_nonneg"
  end
end
