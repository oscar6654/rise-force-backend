class SellerTarget < ApplicationRecord
  belongs_to :seller
  belongs_to :branch, optional: true

  enum :period_type, { daily: 0, mtd: 1, monthly: 2 }, prefix: :period

  def self.for_month(month = Date.current.beginning_of_month)
    where(period_date: month).where(period_type: [:mtd, :monthly])
  end
end
