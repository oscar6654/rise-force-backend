class CreateManagers < ActiveRecord::Migration[8.1]
  def change
    create_table :managers do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.string :pin_digest
      t.references :branch, foreign_key: true, null: true # nil = all branches
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :managers, :code, unique: true

    # A seller is managed by 0..1 manager (the manager sees this seller's team view).
    add_reference :sellers, :manager, foreign_key: { to_table: :managers }, null: true
  end
end
