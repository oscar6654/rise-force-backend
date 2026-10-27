class CreateFulfillmentOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :fulfillment_orders do |t|
      t.references :warehouse, null: false, foreign_key: true
      t.references :order, null: true, foreign_key: true   # SFA order (source: sfa_order)
      t.references :store, null: true, foreign_key: true
      t.bigint  :parent_fulfillment_order_id               # self-ref for per-owner splits
      t.string  :reference_no, null: false
      t.integer :source, default: 0, null: false # sfa_order=0, dispatch_csv=1
      # pending=0, allocated=1, assigned=2, picking=3, picked=4, checking=5,
      # checked=6, short=7, dispatched=8, cancelled=9
      t.integer :status, default: 0, null: false
      t.bigint  :assigned_to_id   # warehouse_staff (picker)
      t.bigint  :checked_by_id    # warehouse_staff (checker)
      t.date    :delivery_date
      t.text    :remarks
      t.date    :demand_date
      t.datetime :allocated_at
      t.datetime :picked_at
      t.datetime :checked_at
      t.datetime :dispatched_at
      t.string  :import_batch_uuid

      t.timestamps
    end

    add_index :fulfillment_orders, %i[warehouse_id reference_no], unique: true
    add_index :fulfillment_orders, :parent_fulfillment_order_id
    add_index :fulfillment_orders, :assigned_to_id
    add_index :fulfillment_orders, %i[warehouse_id status]

    create_table :fulfillment_lines do |t|
      t.references :fulfillment_order, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.decimal :qty_demanded,  precision: 14, scale: 2, default: "0.0", null: false
      t.decimal :qty_allocated, precision: 14, scale: 2, default: "0.0", null: false
      t.decimal :qty_picked,    precision: 14, scale: 2, default: "0.0", null: false
      t.decimal :qty_checked,   precision: 14, scale: 2, default: "0.0", null: false
      t.integer :uom, default: 1, null: false    # pc=0, case_uom=1
      t.integer :status, default: 0, null: false # pending=0, allocated=1, short=2, picked=3, checked=4

      t.timestamps
    end
  end
end
