class AddDatesToAssortments < ActiveRecord::Migration[8.1]
  # Optional effective window. NULL = open-ended (always in effect), matching the
  # existing wildcard style of branch/channel/category.
  def change
    add_column :assortments, :effective_from, :date
    add_column :assortments, :effective_to, :date
  end
end
