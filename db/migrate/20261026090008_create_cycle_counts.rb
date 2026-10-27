class CreateCycleCounts < ActiveRecord::Migration[8.1]
  def change
    create_table :cycle_counts do |t|
      t.references :warehouse, null: false, foreign_key: true
      t.references :storage_location, null: false, foreign_key: true
      t.references :product, null: true, foreign_key: true
      t.references :inventory_lot, null: true, foreign_key: true
      t.integer :trigger, default: 0, null: false # scheduled=0, random=1, manual=2, pick_discrepancy=3
      t.integer :status, default: 0, null: false  # pending=0, counting=1, counted=2, reconciled=3, cancelled=4
      t.decimal :system_qty,  precision: 14, scale: 2 # snapshot at count-open (blind to counter)
      t.decimal :counted_qty, precision: 14, scale: 2
      t.decimal :variance,    precision: 14, scale: 2 # counted - system
      t.bigint  :counted_by_id   # warehouse_staff
      t.datetime :counted_at
      t.bigint  :reconciled_by_id # User (console)
      t.datetime :reconciled_at
      t.string  :reason

      t.timestamps
    end

    add_index :cycle_counts, %i[warehouse_id status]
    add_index :cycle_counts, %i[storage_location_id status]
  end
end
