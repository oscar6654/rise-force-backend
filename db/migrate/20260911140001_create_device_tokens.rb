class CreateDeviceTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :device_tokens do |t|
      t.references :seller, foreign_key: true, null: false
      t.string   :device_id
      t.string   :jti, null: false
      t.string   :refresh_token_digest
      t.datetime :refresh_expires_at
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.string   :platform
      t.string   :app_version

      t.timestamps
    end
    add_index :device_tokens, :jti, unique: true
    add_index :device_tokens, [:seller_id, :device_id]
  end
end
