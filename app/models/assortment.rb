class Assortment < ApplicationRecord
  belongs_to :branch, optional: true
  belongs_to :channel, optional: true
  belongs_to :store_category_ref, class_name: "StoreCategory", optional: true
  belongs_to :assortment_type
  has_many :assortment_items, dependent: :destroy
  has_many :products, through: :assortment_items

  enum :status, { active: 0, inactive: 1 }, default: :active

  RESET_PERIODS = [1, 3, 6].freeze # months: monthly / quarterly / half-year

  validates :name, presence: true
  validates :reset_months, inclusion: { in: RESET_PERIODS }
  validate :dates_in_order

  # `assortment_type_code` — the stable key scheme configs / leaderboard use.
  delegate :code, to: :assortment_type, prefix: true, allow_nil: true

  # Active on a date = status active AND within the optional effective window.
  scope :active_on, ->(date = Date.current) {
    where(status: :active)
      .where("effective_from IS NULL OR effective_from <= ?", date)
      .where("effective_to IS NULL OR effective_to >= ?", date)
  }

  # The assortments that apply to a store (most-specific wins; nil
  # branch/channel/category = wildcard). `type_code` restricts to one type.
  def self.resolved_scope_for(store, on: Date.current, type_code: nil)
    scopes = active_on(on)
             .where("branch_id IS NULL OR branch_id = ?", store.branch_id)
             .where("channel_id IS NULL OR channel_id = ?", store.channel_id)
             .where("store_category_ref_id IS NULL OR store_category_ref_id = ?", store.store_category_id)
    if type_code.present?
      type = AssortmentType.find_by(code: type_code)
      return none unless type

      scopes = scopes.where(assortment_type_id: type.id)
    end
    scopes
  end

  # Resolve the must-stock items for a store, most-specific first; a nil
  # branch/channel/category on the assortment acts as a wildcard. `type_code`
  # restricts to one assortment type (nil = every type, merged). `on` is the
  # date the effective window is evaluated against.
  def self.resolved_items_for(store, on: Date.current, type_code: nil)
    AssortmentItem.where(assortment_id: resolved_scope_for(store, on: on, type_code: type_code).select(:id))
  end

  # Start of the "carried" window for a reset period, aligned to the CALENDAR:
  #   1 → start of this month, 3 → start of this quarter (JFM/AMJ/JAS/OND),
  #   6 → start of this half (Jan–Jun / Jul–Dec). Zone-aware local midnight so a
  # presell `ordered_at` (stored UTC) just after midnight isn't dropped. The
  # `assortment_window_mode = trailing` SystemSetting overrides with a rolling
  # window for every assortment.
  def self.window_start_for(reset_months, on = Date.current)
    if SystemSetting.get("assortment_window_mode", "monthly").to_s == "trailing"
      return Time.current - SystemSetting.get("assortment_window_days", 90).to_i.days
    end

    d = on.to_date
    case reset_months.to_i
    when 3 then d.beginning_of_quarter.in_time_zone
    when 6 then (d.month <= 6 ? Date.new(d.year, 1, 1) : Date.new(d.year, 7, 1)).in_time_zone
    else d.beginning_of_month.in_time_zone
    end
  end

  def window_start(on = Date.current)
    self.class.window_start_for(reset_months, on)
  end

  private

  def dates_in_order
    return if effective_from.blank? || effective_to.blank?

    errors.add(:effective_to, "must be on or after the start date") if effective_to < effective_from
  end
end
