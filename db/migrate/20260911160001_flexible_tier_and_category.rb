class FlexibleTierAndCategory < ActiveRecord::Migration[8.1]
  def up
    create_table :product_tiers do |t|
      t.string  :code, null: false
      t.string  :name, null: false
      t.integer :sort_order, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.integer :legacy_int   # temp: maps old enum value for backfill
      t.timestamps
    end
    add_index :product_tiers, :code, unique: true

    create_table :store_categories do |t|
      t.string  :code, null: false
      t.string  :name, null: false
      t.string  :letter                     # A/B/C/D display
      t.integer :sort_order, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.integer :legacy_int
      t.timestamps
    end
    add_index :store_categories, :code, unique: true

    # Seed defaults carrying the legacy enum ints so we can backfill.
    execute <<~SQL
      INSERT INTO product_tiers (code, name, sort_order, active, legacy_int, created_at, updated_at) VALUES
        ('premium','Tier 1 — Premium',1,true,1,now(),now()),
        ('mainstream','Tier 2 — Mainstream',2,true,2,now(),now()),
        ('value','Tier 3 — Value',3,true,3,now(),now());
      INSERT INTO store_categories (code, name, letter, sort_order, active, legacy_int, created_at, updated_at) VALUES
        ('platinum','Platinum','A',1,true,0,now(),now()),
        ('gold','Gold','B',2,true,1,now(),now()),
        ('silver','Silver','C',3,true,2,now(),now()),
        ('bronze','Bronze','D',4,true,3,now(),now());
    SQL

    # FK columns
    add_reference :products, :product_tier, foreign_key: true, null: true
    add_reference :stores, :store_category, foreign_key: true, null: true
    add_reference :pricing_rules, :store_category, foreign_key: true, null: true
    add_reference :pricing_rules, :product_tier, foreign_key: true, null: true
    add_reference :assortments, :store_category_ref, foreign_key: { to_table: :store_categories }, null: true
    add_reference :promo_eligibilities, :store_category_ref, foreign_key: { to_table: :store_categories }, null: true

    # Backfill from the legacy enum ints
    execute <<~SQL
      UPDATE products p SET product_tier_id = t.id FROM product_tiers t WHERE t.legacy_int = p.tier;
      UPDATE stores s SET store_category_id = c.id FROM store_categories c WHERE c.legacy_int = s.category;
      UPDATE pricing_rules r SET store_category_id = c.id FROM store_categories c WHERE c.legacy_int = r.store_category;
      UPDATE pricing_rules r SET product_tier_id = t.id FROM product_tiers t WHERE t.legacy_int = r.product_tier;
      UPDATE assortments a SET store_category_ref_id = c.id FROM store_categories c WHERE c.legacy_int = a.store_category;
      UPDATE promo_eligibilities e SET store_category_ref_id = c.id FROM store_categories c WHERE c.legacy_int = e.store_category;
    SQL

    # Drop legacy enum int columns now that FKs are populated.
    remove_column :products, :tier
    remove_column :stores, :category
    remove_index :pricing_rules, name: "index_pricing_rules_on_version_category_tier"
    remove_column :pricing_rules, :store_category
    remove_column :pricing_rules, :product_tier
    remove_column :assortments, :store_category
    remove_column :promo_eligibilities, :store_category
    add_index :pricing_rules, [:pricing_version_id, :store_category_id, :product_tier_id],
              unique: true, name: "index_pricing_rules_on_version_cat_tier"

    remove_column :product_tiers, :legacy_int
    remove_column :store_categories, :legacy_int
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
