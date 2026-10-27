class AddRequireScanToWarehouseStaffs < ActiveRecord::Migration[8.1]
  def change
    # When true, this staff MUST scan an item to activate a line before entering
    # a quantity (no tap-to-select) — on every scan screen (pick/receive/count).
    add_column :warehouse_staffs, :require_scan, :boolean, default: false, null: false
  end
end
