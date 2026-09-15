class AddVisitToOrders < ActiveRecord::Migration[8.1]
  def change
    add_reference :orders, :visit, foreign_key: true, null: true
  end
end
