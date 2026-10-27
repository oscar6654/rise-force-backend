class AddWarehouseStaffToDeviceTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :device_tokens, :warehouse_staff_id, :bigint
    add_index  :device_tokens, :warehouse_staff_id
  end
end
