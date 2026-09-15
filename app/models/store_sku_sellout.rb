class StoreSkuSellout < ApplicationRecord
  belongs_to :store

  # Confirmed (invoiced) sellout per store × barcode × month, pulled from
  # vcsi_rise. Feeds must-carry "carried" from actual invoices (see
  # Store#carried_dist_keys) alongside SFA presell orders.
  scope :in_window, ->(since) { where("period_date >= ?", since.to_date.beginning_of_month) }
end
