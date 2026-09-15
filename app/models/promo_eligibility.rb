class PromoEligibility < ApplicationRecord
  belongs_to :promo
  belongs_to :branch, optional: true
  belongs_to :channel, optional: true
  belongs_to :store_category_ref, class_name: "StoreCategory", optional: true
end
