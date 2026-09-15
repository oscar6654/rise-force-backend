class AddTypeToAssortments < ActiveRecord::Migration[8.1]
  # distribution / initiative / focus / npd — used for assortment-type
  # achievement gamification and reporting.
  def change
    add_column :assortments, :assortment_type, :integer, default: 0, null: false
    add_index :assortments, :assortment_type
  end
end
