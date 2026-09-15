class CreateSellers < ActiveRecord::Migration[8.1]
  def change
    create_table :sellers do |t|
      t.references :branch, foreign_key: true, null: false
      t.references :user, foreign_key: true, null: true    # optional link to a console login
      t.string   :seller_code, null: false
      t.string   :name, null: false
      t.string   :device_id
      t.datetime :device_registered_at
      t.datetime :last_sync_at
      t.integer  :status, null: false, default: 0
      t.string   :vcsi_sales_rep_ref

      t.timestamps
    end
    add_index :sellers, :seller_code, unique: true
    add_index :sellers, :vcsi_sales_rep_ref
    add_index :sellers, [:branch_id, :status]
  end
end
