class CreateStoreTargets < ActiveRecord::Migration[8.1]
  def change
    create_table :store_targets do |t|
      t.references :store, null: false, foreign_key: true
      t.references :branch, null: true, foreign_key: true
      t.integer :period_type, null: false, default: 2 # mirrors seller_targets: monthly
      t.date :period_date, null: false
      t.decimal :target_amount, precision: 14, scale: 2, null: false, default: 0

      # Transparency: how this target was derived from vcsi_rise history so an
      # end user can see WHY the number is what it is.
      t.decimal :basis_amount, precision: 14, scale: 2   # trailing average before uplift
      t.integer :months_used                             # how many months averaged
      t.decimal :growth_rate, precision: 7, scale: 4      # uplift applied (0.05 = +5%)
      t.datetime :synced_at

      t.timestamps
    end

    add_index :store_targets, [:store_id, :period_type, :period_date], unique: true,
              name: "index_store_targets_natural_key"
  end
end
