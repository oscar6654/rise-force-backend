class CreateStorageLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :storage_locations do |t|
      t.references :warehouse, null: false, foreign_key: true
      t.string  :loc_code, null: false            # scannable bin code, unique per warehouse
      t.string  :name
      t.string  :zone
      t.string  :aisle
      t.string  :bay
      t.string  :level
      t.integer :loc_type, default: 0, null: false # pick_rack/bulk/buffer/high_value/damage/staging/receiving_dock
      t.boolean :pickable, default: true, null: false
      t.boolean :allow_mixed_lots, default: false, null: false
      t.integer :slot_capacity, default: 1, null: false # pallet positions / simultaneous lots
      t.integer :pick_sequence, default: 0, null: false # lower = nearer / golden zone
      # Acceptance rules: a location is a putaway candidate only if it accepts the
      # SKU's abc_class AND brand. Empty array = accepts any.
      t.string  :allowed_abc_classes, array: true, default: []
      t.bigint  :allowed_brand_ids, array: true, default: []
      t.boolean :needs_cycle_count, default: false, null: false
      t.datetime :last_counted_at
      t.integer :status, default: 0, null: false # active=0, inactive=1

      t.timestamps
    end

    add_index :storage_locations, %i[warehouse_id loc_code], unique: true
    add_index :storage_locations, %i[warehouse_id zone]
    add_index :storage_locations, %i[warehouse_id pickable status]
    add_index :storage_locations, :allowed_abc_classes, using: :gin
    add_index :storage_locations, :allowed_brand_ids, using: :gin
  end
end
