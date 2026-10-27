class CreateWarehouseStaffs < ActiveRecord::Migration[8.1]
  def change
    create_table :warehouse_staffs do |t|
      t.references :warehouse, null: false, foreign_key: true
      t.references :seller, null: true, foreign_key: true # optional link to the SFA seller
      t.string  :staff_code, null: false
      t.string  :name, null: false
      t.string  :pin_digest
      # A SET of roles (one staff can receive, putaway, pick, check and/or count).
      t.string  :roles, array: true, default: []
      t.integer :status, default: 0, null: false # active=0, inactive=1
      t.bigint  :brand_ids, array: true, default: [] # owned brands (brand_per_picker routing)
      t.string  :zones, array: true, default: []      # owned zones (zone_per_picker routing)
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :warehouse_staffs, :staff_code, unique: true
    add_index :warehouse_staffs, :roles, using: :gin
    add_index :warehouse_staffs, :brand_ids, using: :gin
  end
end
