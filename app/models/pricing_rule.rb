class PricingRule < ApplicationRecord
  belongs_to :pricing_version
  belongs_to :store_category
  belongs_to :product_tier

  validates :markup_rate, numericality: true
  validates :store_category_id, uniqueness: { scope: [:pricing_version_id, :product_tier_id] }
end
