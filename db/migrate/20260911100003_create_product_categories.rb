class CreateProductCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :product_categories do |t|
      t.string  :code, null: false
      t.string  :name, null: false
      t.integer :status, null: false, default: 0

      t.timestamps
    end
    add_index :product_categories, :code, unique: true
  end
end
