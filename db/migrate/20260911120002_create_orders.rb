class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.string   :client_uuid, null: false             # offline idempotency
      t.references :seller, foreign_key: true, null: false
      t.references :store,  foreign_key: true, null: false
      t.references :branch, foreign_key: true, null: false   # denormalized for batching/scoping
      t.references :route,  foreign_key: true, null: true
      t.references :order_batch, foreign_key: true, null: true
      t.references :pricing_version, foreign_key: true, null: true
      t.string   :order_number
      t.datetime :ordered_at
      t.datetime :synced_at
      t.integer  :status, null: false, default: 0      # submitted/batched/downloaded/invoiced/cancelled
      t.decimal  :total_amount, precision: 14, scale: 2, null: false, default: 0
      t.jsonb    :promo_summary, null: false, default: {}
      t.text     :notes

      t.timestamps
    end
    add_index :orders, :client_uuid, unique: true
    add_index :orders, :order_number, unique: true, where: "order_number IS NOT NULL"
    add_index :orders, [:branch_id, :seller_id, :status]
    add_index :orders, [:store_id, :ordered_at]

    create_table :order_lines do |t|
      t.references :order, foreign_key: true, null: false
      t.references :product, foreign_key: true, null: false
      t.references :promo, foreign_key: true, null: true
      t.integer  :line_type, null: false, default: 0   # sale / promo_free_good
      t.decimal  :quantity, precision: 12, scale: 2, null: false, default: 0
      t.integer  :uom, null: false, default: 0         # pc / case
      t.decimal  :base_price, precision: 12, scale: 2, null: false, default: 0
      t.decimal  :markup_rate, precision: 7, scale: 4, null: false, default: 0
      t.decimal  :unit_price, precision: 12, scale: 2, null: false, default: 0
      t.decimal  :line_discount, precision: 12, scale: 2, null: false, default: 0
      t.decimal  :line_total, precision: 14, scale: 2, null: false, default: 0
      t.string   :vcsi_product_ref

      t.timestamps
    end
  end
end
