class Assortment < ApplicationRecord
  belongs_to :branch, optional: true
  belongs_to :channel, optional: true
  belongs_to :store_category_ref, class_name: "StoreCategory", optional: true
  belongs_to :assortment_type
  has_many :assortment_items, dependent: :destroy
  has_many :products, through: :assortment_items

  enum :status, { active: 0, inactive: 1 }, default: :active

  validates :name, presence: true
  validate :dates_in_order

  # `assortment_type_code` — the stable key scheme configs / leaderboard use.
  delegate :code, to: :assortment_type, prefix: true, allow_nil: true

  # Active on a date = status active AND within the optional effective window.
  scope :active_on, ->(date = Date.current) {
    where(status: :active)
      .where("effective_from IS NULL OR effective_from <= ?", date)
      .where("effective_to IS NULL OR effective_to >= ?", date)
  }

  # Resolve the must-stock items for a store, most-specific first; a nil
  # branch/channel/category on the assortment acts as a wildcard. `type_code`
  # restricts to one assortment type (nil = every type, merged). `on` is the
  # date the effective window is evaluated against.
  def self.resolved_items_for(store, on: Date.current, type_code: nil)
    scopes = active_on(on)
             .where("branch_id IS NULL OR branch_id = ?", store.branch_id)
             .where("channel_id IS NULL OR channel_id = ?", store.channel_id)
             .where("store_category_ref_id IS NULL OR store_category_ref_id = ?", store.store_category_id)
    if type_code.present?
      type = AssortmentType.find_by(code: type_code)
      return AssortmentItem.none unless type

      scopes = scopes.where(assortment_type_id: type.id)
    end
    AssortmentItem.where(assortment_id: scopes.select(:id))
  end

  private

  def dates_in_order
    return if effective_from.blank? || effective_to.blank?

    errors.add(:effective_to, "must be on or after the start date") if effective_to < effective_from
  end
end
