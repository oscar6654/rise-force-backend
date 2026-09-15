class AddPinToSellers < ActiveRecord::Migration[8.1]
  def change
    add_column :sellers, :pin_digest, :string
  end
end
