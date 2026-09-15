class CreatePricingVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :pricing_versions do |t|
      t.integer :version_number, null: false
      t.string  :name
      t.date    :effective_date, null: false
      t.integer :status, null: false, default: 0     # draft/published/superseded/archived
      t.datetime :published_at
      t.references :published_by, foreign_key: { to_table: :users }, null: true
      t.text    :notes

      t.timestamps
    end
    add_index :pricing_versions, :version_number, unique: true
    add_index :pricing_versions, [:status, :effective_date]

    create_table :pricing_rules do |t|
      t.references :pricing_version, foreign_key: true, null: false
      t.integer :store_category, null: false          # mirrors Store.category
      t.integer :product_tier, null: false            # mirrors Product.tier
      t.decimal :markup_rate, precision: 7, scale: 4, null: false, default: 0

      t.timestamps
    end
    add_index :pricing_rules, [:pricing_version_id, :store_category, :product_tier],
              unique: true, name: "index_pricing_rules_on_version_category_tier"
  end
end
