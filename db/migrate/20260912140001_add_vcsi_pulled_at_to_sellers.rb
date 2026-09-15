class AddVcsiPulledAtToSellers < ActiveRecord::Migration[8.1]
  # When this seller last triggered an on-demand vcsi_rise pull from the app.
  # Used to throttle per-seller pulls (distinct from last_sync_at, which the
  # global sellout job sets).
  def change
    add_column :sellers, :vcsi_pulled_at, :datetime
  end
end
