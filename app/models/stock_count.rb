class StockCount < ApplicationRecord
  belongs_to :visit, optional: true   # seller flow: count during a visit
  belongs_to :store, optional: true   # diser flow: store-scoped, no visit
  belongs_to :product

  enum :prefilled_from, { none: 0, last_order: 1, last_visit: 2 }, prefix: :prefill

  validates :client_uuid, presence: true, uniqueness: true
  validate :store_or_visit_present

  # The count date, offline-safe: explicit device date, else the visit day, else
  # when the row was created. And the store, from either grain.
  DATE_SQL  = "COALESCE(stock_counts.counted_on, visits.visit_date, stock_counts.created_at::date)".freeze
  STORE_SQL = "COALESCE(stock_counts.store_id, visits.store_id)".freeze

  # Counts for one store across BOTH grains (visit-scoped or store-scoped).
  scope :for_store, ->(store_id) {
    left_joins(:visit).where("stock_counts.store_id = :s OR visits.store_id = :s", s: store_id)
  }

  def effective_store_id
    store_id || visit&.store_id
  end

  def counted_date
    counted_on || visit&.visit_date || created_at&.to_date
  end

  private

  def store_or_visit_present
    return if store_id.present? || visit_id.present?

    errors.add(:base, "must belong to a store or a visit")
  end
end
