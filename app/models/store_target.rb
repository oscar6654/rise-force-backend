class StoreTarget < ApplicationRecord
  belongs_to :store
  belongs_to :branch, optional: true

  enum :period_type, { daily: 0, mtd: 1, monthly: 2 }, prefix: :period

  def self.for_month(month = Date.current.beginning_of_month)
    where(period_date: month).where(period_type: [:mtd, :monthly])
  end

  # Human-readable note on how the number was derived, for the UI.
  def basis_label
    return nil if months_used.blank?

    pct = growth_rate.to_d.zero? ? "no uplift" : "+#{(growth_rate.to_d * 100).round(1)}%"
    "#{months_used}-mo avg #{pct}"
  end
end
