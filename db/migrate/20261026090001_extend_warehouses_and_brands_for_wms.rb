class ExtendWarehousesAndBrandsForWms < ActiveRecord::Migration[8.1]
  def change
    # WMS toggle + picker-assignment strategy live on the existing warehouse master.
    add_column :warehouses, :wms_enabled, :boolean, default: false, null: false
    add_column :warehouses, :allocation_strategy, :integer, default: 0, null: false # brand_per_picker=0, zone_per_picker=1

    # Brands flagged high_value route putaway to secured high-value shelf locations.
    add_column :brands, :high_value, :boolean, default: false, null: false
  end
end
