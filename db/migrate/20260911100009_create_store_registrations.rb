class CreateStoreRegistrations < ActiveRecord::Migration[8.1]
  def change
    create_table :store_registrations do |t|
      t.references :seller, foreign_key: true, null: false
      t.references :branch, foreign_key: true, null: false
      t.references :channel, foreign_key: true, null: true  # proposed channel
      t.string  :client_uuid, null: false                   # offline idempotency

      t.string  :name, null: false
      t.string  :owner_name
      t.string  :contact_number
      t.string  :address
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      t.integer :proposed_category, null: false, default: 0

      t.integer :status, null: false, default: 0            # pending/approved/rejected
      t.references :duplicate_of_store, foreign_key: { to_table: :stores }, null: true
      t.decimal :duplicate_score, precision: 5, scale: 2
      t.jsonb   :duplicate_flags, null: false, default: []

      t.references :provisional_store, foreign_key: { to_table: :stores }, null: true
      t.references :created_store, foreign_key: { to_table: :stores }, null: true
      t.references :reviewed_by, foreign_key: { to_table: :users }, null: true
      t.datetime :reviewed_at
      t.text :rejection_reason

      t.timestamps
    end
    add_index :store_registrations, :client_uuid, unique: true
    add_index :store_registrations, [:branch_id, :status]
  end
end
