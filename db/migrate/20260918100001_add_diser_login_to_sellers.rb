class AddDiserLoginToSellers < ActiveRecord::Migration[8.1]
  def change
    add_column :sellers, :diser_code, :string
    add_column :sellers, :diser_name, :string
    add_column :sellers, :diser_pin_digest, :string
    add_index :sellers, :diser_code, unique: true, where: "diser_code IS NOT NULL"
  end
end
