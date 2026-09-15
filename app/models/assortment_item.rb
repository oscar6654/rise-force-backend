class AssortmentItem < ApplicationRecord
  belongs_to :assortment
  belongs_to :product

  validates :assortment_id, uniqueness: { scope: :product_id }

  scope :must_stock, -> { where(must_stock: true) }
end
