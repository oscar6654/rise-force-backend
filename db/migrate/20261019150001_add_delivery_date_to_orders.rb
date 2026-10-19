class AddDeliveryDateToOrders < ActiveRecord::Migration[8.1]
  def change
    # Requested delivery date, captured at order review. Only filled for sellers
    # in the sections configured in SystemSetting `delivery_date_sections`.
    add_column :orders, :delivery_date, :date
  end
end
