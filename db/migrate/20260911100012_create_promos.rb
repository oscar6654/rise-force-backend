class CreatePromos < ActiveRecord::Migration[8.1]
  def change
    create_table :promos do |t|
      t.string  :code, null: false
      t.string  :name, null: false
      t.integer :mechanic_type, null: false, default: 0  # discount_percent/amount/buy_x_get_y/bundle_price/free_goods
      t.text    :description
      t.date    :start_date
      t.date    :end_date
      t.integer :status, null: false, default: 0         # scheduled/active/ended/cancelled
      t.jsonb   :config, null: false, default: {}
      t.references :created_by, foreign_key: { to_table: :users }, null: true

      t.timestamps
    end
    add_index :promos, :code, unique: true
    add_index :promos, [:status, :start_date, :end_date]

    create_table :promo_lines do |t|
      t.references :promo, foreign_key: true, null: false
      t.references :product, foreign_key: true, null: true
      t.integer :role, null: false, default: 0           # qualifying/reward
      t.integer :min_qty
      t.integer :reward_qty
      t.decimal :discount_rate, precision: 7, scale: 4
      t.decimal :discount_amount, precision: 12, scale: 2
      t.decimal :fixed_price, precision: 12, scale: 2

      t.timestamps
    end

    create_table :promo_eligibilities do |t|
      t.references :promo, foreign_key: true, null: false
      t.references :branch, foreign_key: true, null: true
      t.references :channel, foreign_key: true, null: true
      t.integer :store_category

      t.timestamps
    end
    add_index :promo_eligibilities, [:promo_id, :channel_id, :store_category],
              name: "index_promo_eligibilities_scope"
  end
end
