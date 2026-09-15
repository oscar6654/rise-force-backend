class CreateAssortments < ActiveRecord::Migration[8.1]
  def change
    create_table :assortments do |t|
      t.string     :name, null: false
      t.references :branch, foreign_key: true, null: true   # null = all branches
      t.references :channel, foreign_key: true, null: true  # null = any channel
      t.integer    :store_category                          # null = any category
      t.integer    :status, null: false, default: 0

      t.timestamps
    end

    create_table :assortment_items do |t|
      t.references :assortment, foreign_key: true, null: false
      t.references :product, foreign_key: true, null: false
      t.boolean    :must_stock, null: false, default: true
      t.integer    :priority, null: false, default: 0

      t.timestamps
    end
    add_index :assortment_items, [:assortment_id, :product_id], unique: true
  end
end
