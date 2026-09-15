class CompetitorPriceCheck < ApplicationRecord
  belongs_to :visit
  belongs_to :product, optional: true

  validates :client_uuid, presence: true, uniqueness: true
end
