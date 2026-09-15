class CreateBranches < ActiveRecord::Migration[8.1]
  def change
    create_table :branches do |t|
      t.string  :code, null: false
      t.string  :name, null: false
      t.string  :region
      t.integer :status, null: false, default: 0
      t.string  :vcsi_branch_ref
      t.string  :timezone, null: false, default: "Asia/Manila"

      t.timestamps
    end

    add_index :branches, :code, unique: true
    add_index :branches, :vcsi_branch_ref
  end
end
