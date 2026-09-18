class AddRoleToDeviceTokens < ActiveRecord::Migration[8.1]
  def change
    # The app login now issues tokens for three roles: seller (full), diser
    # (stock-check only), manager (team view). seller_id is the principal for
    # seller/diser; manager_id for manager.
    add_column :device_tokens, :role, :string, default: "seller", null: false
    add_column :device_tokens, :manager_id, :bigint
    add_index :device_tokens, :manager_id
    change_column_null :device_tokens, :seller_id, true
  end
end
