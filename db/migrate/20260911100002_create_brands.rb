class CreateBrands < ActiveRecord::Migration[8.1]
  def change
    create_table :brands do |t|
      t.string  :code, null: false
      t.string  :name, null: false
      t.integer :sort_order, null: false, default: 0
      t.integer :status, null: false, default: 0

      t.timestamps
    end
    add_index :brands, :code, unique: true
  end
end
