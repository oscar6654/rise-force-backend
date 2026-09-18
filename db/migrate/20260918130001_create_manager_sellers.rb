class CreateManagerSellers < ActiveRecord::Migration[8.1]
  def up
    # Many-to-many: a manager is tagged to a chosen set of sellers, and a seller
    # can sit under several managers (e.g. a supervisor AND a branch manager).
    create_table :manager_sellers do |t|
      t.references :manager, null: false, foreign_key: true
      t.references :seller,  null: false, foreign_key: true
      t.timestamps
    end
    add_index :manager_sellers, [:manager_id, :seller_id], unique: true

    # Carry over any single-manager assignments made before this change.
    execute <<~SQL.squish
      INSERT INTO manager_sellers (manager_id, seller_id, created_at, updated_at)
      SELECT manager_id, id, NOW(), NOW() FROM sellers WHERE manager_id IS NOT NULL
    SQL

    remove_reference :sellers, :manager, foreign_key: { to_table: :managers }
  end

  def down
    add_reference :sellers, :manager, foreign_key: { to_table: :managers }, null: true
    execute <<~SQL.squish
      UPDATE sellers SET manager_id = ms.manager_id
      FROM manager_sellers ms WHERE ms.seller_id = sellers.id
    SQL
    drop_table :manager_sellers
  end
end
