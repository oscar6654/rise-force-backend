class PromoLine < ApplicationRecord
  belongs_to :promo
  belongs_to :product, optional: true

  enum :role, { qualifying: 0, reward: 1 }, prefix: :role
end
