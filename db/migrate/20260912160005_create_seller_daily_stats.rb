class CreateSellerDailyStats < ActiveRecord::Migration[8.1]
  def change
    create_table :seller_daily_stats do |t|
      t.references :seller, null: false, foreign_key: true
      t.date :stat_date, null: false
      t.integer :planned, null: false, default: 0        # stores due on the route that day
      t.integer :visited, null: false, default: 0        # planned stores actually visited
      t.integer :productive_calls, null: false, default: 0 # visits closed with an order
      t.integer :orders_count, null: false, default: 0
      t.boolean :goal_met, null: false, default: false   # completed the day's route
      t.timestamps
    end
    add_index :seller_daily_stats, %i[seller_id stat_date], unique: true
  end
end
