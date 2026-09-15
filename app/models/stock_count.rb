class StockCount < ApplicationRecord
  belongs_to :visit
  belongs_to :product

  enum :prefilled_from, { none: 0, last_order: 1, last_visit: 2 }, prefix: :prefill

  validates :client_uuid, presence: true, uniqueness: true
end
