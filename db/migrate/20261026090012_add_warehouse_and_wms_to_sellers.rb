class AddWarehouseAndWmsToSellers < ActiveRecord::Migration[8.1]
  def change
    # A seller is tied to one warehouse; when wms_enabled, that seller's orders
    # flow through the WMS (pick/pack/dispatch) instead of the OSB batch download.
    # A seller whose warehouse is NOT wms_enabled (or who is not wms_enabled)
    # keeps going through OSB batch download, unchanged.
    add_reference :sellers, :warehouse, null: true, foreign_key: true
    add_column :sellers, :wms_enabled, :boolean, default: false, null: false
  end
end
