class CreateAssortmentTypes < ActiveRecord::Migration[8.1]
  # Assortment "type" was a fixed integer enum (distribution/initiative/focus/npd).
  # Promote it to an admin-managed lookup table so new types can be added in the
  # console without a deploy. Existing rows are backfilled by code.
  SEED = [%w[distribution Distribution], %w[initiative Initiative], %w[focus Focus], %w[npd NPD]].freeze
  ENUM_TO_CODE = { 0 => "distribution", 1 => "initiative", 2 => "focus", 3 => "npd" }.freeze

  def up
    create_table :assortment_types do |t|
      t.string  :code, null: false
      t.string  :name, null: false
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :assortment_types, :code, unique: true

    now = Time.current
    SEED.each_with_index do |(code, name), i|
      execute ActiveRecord::Base.sanitize_sql([
        "INSERT INTO assortment_types (code, name, position, active, created_at, updated_at) " \
        "VALUES (?, ?, ?, TRUE, ?, ?)", code, name, i, now, now
      ])
    end

    add_reference :assortments, :assortment_type, foreign_key: true, index: true

    ENUM_TO_CODE.each do |int, code|
      execute ActiveRecord::Base.sanitize_sql([
        "UPDATE assortments SET assortment_type_id = (SELECT id FROM assortment_types WHERE code = ?) " \
        "WHERE assortment_type = ?", code, int
      ])
    end
    # Safety: anything unmapped falls back to distribution.
    execute "UPDATE assortments SET assortment_type_id = " \
            "(SELECT id FROM assortment_types WHERE code = 'distribution') WHERE assortment_type_id IS NULL"

    change_column_null :assortments, :assortment_type_id, false
    remove_column :assortments, :assortment_type
  end

  def down
    add_column :assortments, :assortment_type, :integer, default: 0, null: false
    add_index :assortments, :assortment_type
    ENUM_TO_CODE.each do |int, code|
      execute ActiveRecord::Base.sanitize_sql([
        "UPDATE assortments SET assortment_type = ? " \
        "WHERE assortment_type_id = (SELECT id FROM assortment_types WHERE code = ?)", int, code
      ])
    end
    remove_reference :assortments, :assortment_type
    drop_table :assortment_types
  end
end
