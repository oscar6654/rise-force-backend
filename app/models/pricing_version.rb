class PricingVersion < ApplicationRecord
  has_many :pricing_rules, dependent: :destroy
  belongs_to :published_by, class_name: "User", optional: true

  enum :status, { draft: 0, published: 1, superseded: 2, archived: 3 }, default: :draft

  validates :version_number, presence: true, uniqueness: true
  validates :effective_date, presence: true

  before_validation :assign_version_number, on: :create

  # The version in effect for a given date (latest published on/before it).
  def self.current(on: Date.current)
    published.where("effective_date <= ?", on)
             .order(effective_date: :desc, version_number: :desc)
             .first
  end

  # Publish this version and supersede the previously-current one.
  def publish!(user)
    transaction do
      PricingVersion.published.where.not(id: id).update_all(status: PricingVersion.statuses[:superseded])
      update!(status: :published, published_at: Time.current, published_by: user)
    end
  end

  # store_category / product_tier may be records or their codes.
  def rule_for(store_category, product_tier)
    cat = store_category.is_a?(StoreCategory) ? store_category : StoreCategory.find_by(code: store_category.to_s)
    tier = product_tier.is_a?(ProductTier) ? product_tier : ProductTier.find_by(code: product_tier.to_s)
    pricing_rules.find_by(store_category_id: cat&.id, product_tier_id: tier&.id)
  end

  private

  def assign_version_number
    self.version_number ||= (PricingVersion.maximum(:version_number) || 0) + 1
  end
end
