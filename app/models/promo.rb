class Promo < ApplicationRecord
  has_many :promo_lines, dependent: :destroy
  has_many :promo_eligibilities, dependent: :destroy
  belongs_to :created_by, class_name: "User", optional: true

  accepts_nested_attributes_for :promo_lines, allow_destroy: true,
    reject_if: ->(attrs) { attrs["it_barcode"].blank? && attrs["min_qty"].blank? && attrs["reward_qty"].blank? }

  enum :mechanic_type, {
    discount_percent: 0, discount_amount: 1, buy_x_get_y: 2, bundle_price: 3, free_goods: 4,
    # Volume deal: tiers in `config` — {basis: "pieces"|"amount", tiers: [{min, rate}|{min, amount}]}.
    # e.g. "4% off 18-71 pcs, 7% off 72+" or "₱100 off ≥₱1200, ₱300 off ≥₱3000". Qualifying
    # SKUs come from role:qualifying promo_lines (empty = whole order, amount basis).
    tiered_discount: 5,
    # Combo: buy SPECIFIC items, EACH at its own minimum pieces (role:qualifying
    # promo_lines with min_qty) → X% off those items (ex-VAT). Rate in
    # config["rate"] (0.10 = 10%). All items must meet their min for it to apply.
    combo_percent: 6
  }

  # X% rate for a combo_percent promo (0.10 = 10%).
  def combo_rate
    config&.dig("rate").to_d
  end

  # Parse the compact combo-items syntax "barcode:minpieces|barcode:minpieces".
  def self.parse_combo_items(str)
    str.to_s.split(/[|;]/).filter_map do |part|
      bc, min = part.split(":").map { |s| s.to_s.strip }
      next if bc.blank? || min.blank?

      { "barcode" => bc, "min" => min.to_i }
    end
  end

  # Sorted discount tiers from config (ascending by threshold). Each: {min, rate|amount}.
  def tiers
    Array(config&.dig("tiers")).map { |t| t.is_a?(Hash) ? t.transform_keys(&:to_s) : t }
                               .sort_by { |t| t["min"].to_f }
  end

  def tier_basis
    config&.dig("basis").presence || "pieces"
  end

  # Parse the compact tier syntax "min:value|min:value" into config tier hashes.
  # value is a rate (0.04) for the "pieces" basis, or a peso amount (100) for "amount".
  def self.parse_tiers(str, basis)
    key = basis.to_s == "amount" ? "amount" : "rate"
    str.to_s.split(/[|;,]/).filter_map do |part|
      min, val = part.split(":").map { |s| s.to_s.strip }
      next if min.blank? || val.blank?

      { "min" => min.to_f, key => val.to_f }
    end.sort_by { |t| t["min"] }
  end
  enum :status, { scheduled: 0, active: 1, ended: 2, cancelled: 3 }, default: :scheduled

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true

  scope :live_on, ->(date) {
    where(status: :active).where("start_date IS NULL OR start_date <= ?", date)
                          .where("end_date IS NULL OR end_date >= ?", date)
  }

  # Promos a store is eligible for, honouring eligibility scopes (nil = any).
  def self.eligible_for(store)
    joins("LEFT JOIN promo_eligibilities pe ON pe.promo_id = promos.id")
      .where("pe.id IS NULL OR ((pe.branch_id IS NULL OR pe.branch_id = :b) " \
             "AND (pe.channel_id IS NULL OR pe.channel_id = :c) " \
             "AND (pe.store_category_ref_id IS NULL OR pe.store_category_ref_id = :cat))",
             b: store.branch_id, c: store.channel_id, cat: store.store_category_id)
      .distinct
  end

  # ---- Per-store availment limit -------------------------------------------
  # per_store_limit: max avails per store within the promo's active window.
  # NULL / 0 = unlimited. An "avail" = one order that used this promo.
  def unlimited_per_store?
    per_store_limit.blank? || per_store_limit.to_i <= 0
  end

  # How many times a store has already availed this promo, counted within the
  # promo's active window (order_lines carry promo_id; one order = one avail).
  def avails_for(store)
    scope = Order.where.not(status: :cancelled)
                 .where(store_id: store.is_a?(Store) ? store.id : store)
                 .where(id: OrderLine.where(promo_id: id).select(:order_id))
    scope = scope.where("orders.ordered_at >= ?", start_date.beginning_of_day) if start_date
    scope = scope.where("orders.ordered_at <= ?", end_date.end_of_day) if end_date
    scope.distinct.count
  end

  # Is another avail of this promo allowed for the store right now?
  def available_for?(store)
    return true if unlimited_per_store?

    avails_for(store) < per_store_limit.to_i
  end

  # Recompute status from dates (used by a daily refresh job).
  def refresh_status!(today = Date.current)
    return if cancelled?

    new_status =
      if start_date && today < start_date then :scheduled
      elsif end_date && today > end_date then :ended
      else :active
      end
    update!(status: new_status) unless status == new_status.to_s
  end
end
