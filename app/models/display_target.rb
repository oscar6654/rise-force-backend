class DisplayTarget < ApplicationRecord
  belongs_to :display_campaign
  belongs_to :store, optional: true # CU code may be outside our store master

  validates :store_code, :promotion_name, presence: true

  # Blank brand = the target is met by ANY brand in the category.
  def brand_specific?
    brand.present?
  end
end
