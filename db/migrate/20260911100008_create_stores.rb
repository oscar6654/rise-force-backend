class CreateStores < ActiveRecord::Migration[8.1]
  def change
    create_table :stores do |t|
      t.references :branch, foreign_key: true, null: false
      t.references :channel, foreign_key: true, null: true
      t.references :route, foreign_key: true, null: true

      t.string  :store_code                   # permanent code (nil while provisional)
      t.string  :provisional_code             # temporary code assigned at field registration
      t.string  :name, null: false
      t.string  :owner_name
      t.string  :contact_number
      t.string  :address
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6

      t.integer :category, null: false, default: 0   # platinum/gold/silver/bronze (A/B/C/D)
      t.integer :status, null: false, default: 1     # provisional/active/inactive/closed/rejected

      # Visit frequency block (F2/F4 + week pattern + fixed day + sequence)
      t.integer :visit_frequency, null: false, default: 4   # f2:2, f4:4
      t.integer :week_pattern, null: false, default: 0      # every_week/weeks_1_3/weeks_2_4
      t.integer :visit_day                                  # mon..sat
      t.integer :visit_sequence

      t.string  :vcsi_customer_ref
      # Soft link (no FK) to avoid a circular constraint with store_registrations.
      t.references :store_registration, foreign_key: false, null: true, index: true

      t.timestamps
    end

    add_index :stores, :store_code, unique: true, where: "store_code IS NOT NULL"
    add_index :stores, :provisional_code, unique: true, where: "provisional_code IS NOT NULL"
    add_index :stores, :vcsi_customer_ref
    add_index :stores, [:branch_id, :category, :status]
    add_index :stores, [:route_id, :visit_day, :visit_sequence]
    # Trigram index for fuzzy duplicate detection on name.
    add_index :stores, :name, using: :gin, opclass: :gin_trgm_ops, name: "index_stores_on_name_trgm"
  end
end
