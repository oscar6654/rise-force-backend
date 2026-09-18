class AddPrimarySellerToSellers < ActiveRecord::Migration[8.1]
  def change
    # One physical rep who covers 2 branches has 2-3 seller records (one per
    # vcsi sales_rep code / branch). Link the extras to a primary so ONE app
    # login sees them all combined — no merge, each keeps its own rep + syncs.
    add_reference :sellers, :primary_seller, foreign_key: { to_table: :sellers }, null: true
  end
end
