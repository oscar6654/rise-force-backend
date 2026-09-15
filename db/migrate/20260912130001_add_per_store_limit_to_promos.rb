class AddPerStoreLimitToPromos < ActiveRecord::Migration[8.1]
  # Max times a store may avail this promo within its active window
  # (start_date..end_date). NULL / 0 = unlimited.
  def change
    add_column :promos, :per_store_limit, :integer
  end
end
