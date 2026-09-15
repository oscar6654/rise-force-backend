class CreateRoutes < ActiveRecord::Migration[8.1]
  def change
    create_table :routes do |t|
      t.references :seller, foreign_key: true, null: true
      t.references :branch, foreign_key: true, null: false
      t.string  :code, null: false
      t.string  :name
      t.integer :status, null: false, default: 0

      t.timestamps
    end
    add_index :routes, [:branch_id, :code], unique: true
  end
end
