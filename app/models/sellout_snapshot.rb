class SelloutSnapshot < ApplicationRecord
  belongs_to :branch, optional: true
  belongs_to :seller, optional: true
  belongs_to :store, optional: true
  belongs_to :product, optional: true

  enum :period_type, { daily: 0, mtd: 1, monthly: 2 }, prefix: :period

  # Actual sellout (from vcsi_rise) for a seller in the current month.
  def self.mtd_actual_for(seller, month: Date.current.beginning_of_month)
    where(seller: seller, period_type: :mtd, period_date: month).sum(:amount)
  end

  # Store-grain snapshots have store_id set and seller_id nil (a store's actual
  # is attributed to the customer, not a rep). Confirmed actual for a store.
  def self.store_mtd_actual_for(store, month: Date.current.beginning_of_month)
    where(store: store, seller_id: nil, period_type: :mtd, period_date: month).sum(:amount)
  end

  # When the store's confirmed sellout was last pulled from vcsi_rise — the
  # cutoff for "presell placed since the last sync" in the reconciling actual.
  def self.store_last_synced_at(store, month: Date.current.beginning_of_month)
    where(store: store, seller_id: nil, period_type: :mtd, period_date: month).maximum(:synced_at)
  end

  # When the seller's confirmed sellout was last pulled — cutoff for the route
  # card's "to invoice" (presell placed since the last sync).
  def self.seller_last_synced_at(seller, month: Date.current.beginning_of_month)
    where(seller: seller, period_type: :mtd, period_date: month).maximum(:synced_at)
  end
end
