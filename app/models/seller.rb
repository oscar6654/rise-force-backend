class Seller < ApplicationRecord
  # Per-seller mobile PIN (bcrypt). Set in the seller master; the app logs in
  # with seller_code + this PIN. `validations: false` so a blank PIN is allowed
  # (falls back to the shared PIN until one is set).
  has_secure_password :pin, validations: false
  # A diser (merchandiser helper) shares the seller's stores but logs in with
  # their own credentials and only does stock checks. Blank = no diser login.
  has_secure_password :diser_pin, validations: false

  belongs_to :branch
  belongs_to :user, optional: true
  # Field managers who oversee this seller (many-to-many; a seller may report to
  # both a supervisor and a branch manager).
  has_many :manager_sellers, dependent: :destroy
  has_many :managers, through: :manager_sellers
  # Login group: extra seller records (2nd branch / 2nd vcsi rep code) point to a
  # primary so one login sees them all combined. Each keeps its own rep + syncs.
  belongs_to :primary_seller, class_name: "Seller", optional: true
  has_many :secondary_sellers, class_name: "Seller", foreign_key: :primary_seller_id, dependent: :nullify

  # Every seller_id in this login's group (works logging in as any member).
  def login_group_ids
    root = primary_seller_id || id
    Seller.where("id = :r OR primary_seller_id = :r", r: root).pluck(:id)
  end

  def grouped_login?
    primary_seller_id.present? || secondary_sellers.exists?
  end
  has_many :routes, dependent: :nullify
  has_many :stores, dependent: :nullify              # directly-assigned stores
  has_many :route_stores, through: :routes, source: :stores
  has_many :store_registrations, dependent: :nullify

  enum :status, { active: 0, suspended: 1, inactive: 2 }, default: :active

  validates :seller_code, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  # A diser code must be distinct from every seller code — otherwise the login
  # resolves to the SELLER (seller_code is matched first) and the diser gets the
  # full app instead of the stock-check-only view.
  validate :diser_code_not_a_seller_code

  def diser_code_not_a_seller_code
    return if diser_code.blank?

    clash = seller_code.to_s.casecmp?(diser_code) ||
            Seller.where.not(id: id).where("lower(seller_code) = ?", diser_code.downcase).exists?
    errors.add(:diser_code, "must be different from every seller code") if clash
  end

  has_many :seller_targets, dependent: :destroy
  has_many :seller_daily_stats, dependent: :destroy
  has_many :sellout_snapshots, dependent: :destroy
  has_many :sku_sellout_snapshots, dependent: :destroy
  has_many :orders, dependent: :restrict_with_error

  def pin_set?
    pin_digest.present?
  end

  def diser_pin_set?
    diser_pin_digest.present?
  end

  def diser_login?
    diser_code.present?
  end

  scope :for_branches, ->(ids) { where(branch_id: ids) }

  def sync_stale?
    last_actual_sync_at.nil? || last_actual_sync_at < 24.hours.ago
  end

  # Most recent refresh of this seller's actuals — whichever is newer, the
  # global sellout job (last_sync_at) or the seller's own app pull (vcsi_pulled_at).
  def last_actual_sync_at
    [last_sync_at, vcsi_pulled_at].compact.max
  end

  # True when the freshest refresh came from the seller's own app pull.
  def last_sync_from_app?
    vcsi_pulled_at.present? && vcsi_pulled_at == last_actual_sync_at
  end

  # Headline target vs actual for the month — reused by the app refresh/summary.
  def headline(month = Date.current.beginning_of_month)
    target = target_for(month)
    confirmed = confirmed_actual(month)
    presell = pending_presell(month)
    blended = confirmed + presell
    {
      period: month, target_amount: target,
      confirmed_actual: confirmed, presell_pending: presell, blended_actual: blended,
      attainment_pct: (target.to_d.positive? ? (blended / target * 100).round : nil),
      last_sync_at: last_actual_sync_at
    }
  end

  # ---- Productive calls (a "call" = a completed visit) ---------------------
  # Productive = the visit was closed with an order. PC% is the classic FMCG
  # coverage-quality KPI: productive calls / total completed calls.
  COMPLETED_CALL_STATUSES = [:closed_with_order, :closed_no_order].freeze

  def calls_in(range)
    Visit.where(seller: self, visit_date: range, status: COMPLETED_CALL_STATUSES).count
  end

  # A completed call is productive when it closed with an order OR an SFA order
  # was placed at that store on the visit day (presell — vcsi_rise confirms it
  # downstream). Blends the visit outcome with actual order activity, so an order
  # taken without a formal "closed with order" checkout still counts.
  def productive_calls_in(range)
    rows = Visit.where(seller: self, visit_date: range, status: COMPLETED_CALL_STATUSES)
                .pluck(:store_id, :visit_date, :status)
    return 0 if rows.empty?

    # Rails maps the enum on pluck, so status comes back as the name string.
    order_days = Order.where(seller: self).where.not(status: :cancelled)
                      .where(ordered_at: range.begin.beginning_of_day..range.end.end_of_day)
                      .pluck(:store_id, :ordered_at).map { |sid, at| [sid, at.to_date] }.to_set
    rows.count { |store_id, date, status| status == "closed_with_order" || order_days.include?([store_id, date]) }
  end

  def productive_call_pct(range = Date.current.beginning_of_month..Date.current)
    total = calls_in(range)
    total.positive? ? (productive_calls_in(range).to_f / total * 100).round : nil
  end

  # ---- Route productivity, month-running (leaderboard PC%) ------------------
  # "Stores ordered vs actual route", summed across the whole month so far.
  # Every SCHEDULED store-day counts (a store due 4x this month = 4 slots); a
  # slot is productive when that store got an order on that scheduled day. So a
  # seller who ordered at 1 of 8 stores due today, and nothing else this month,
  # reads 1/8 — and it accumulates as the month runs, matching the daily tile.
  def route_productive_call_pct(month = Date.current.beginning_of_month, upto: Date.current)
    Seller.route_pc_for_ids(login_group_ids, month, upto)
  end

  # Month-running route productivity across a SET of seller ids (a login group or
  # a manager's team): scheduled route store-days ordered / total scheduled.
  def self.route_pc_for_ids(ids, month = Date.current.beginning_of_month, upto = Date.current)
    planned = Store.joins(:route).where(routes: { seller_id: ids }).pluck(:id, :visit_day, :week_pattern)
    return nil if planned.empty?

    order_days = Order.where(seller_id: ids).where.not(status: :cancelled)
                      .where(ordered_at: month.beginning_of_day..upto.end_of_day)
                      .pluck(:store_id, :ordered_at)
                      .map { |sid, at| [sid, at.to_date] }.to_set

    scheduled = 0
    productive = 0
    (month..upto).each do |date|
      wday = date.wday
      planned.each do |sid, visit_day, week_pattern|
        next unless due_on_day?(visit_day, week_pattern, date, wday)

        scheduled += 1
        productive += 1 if order_days.include?([sid, date])
      end
    end
    scheduled.positive? ? (productive * 100.0 / scheduled).round : nil
  end

  # Frequency rule check without materializing a Store (mirrors Store#due_on?).
  # visit_day/week_pattern arrive as the mapped enum strings from pluck.
  def self.due_on_day?(visit_day, week_pattern, date, wday = date.wday)
    return false if visit_day.nil?
    return false unless Store.visit_days[visit_day] == wday

    case week_pattern
    when "every_week" then true
    when "weeks_1_3"  then ((date.day - 1) / 7).even? # weeks 1,3 => index 0,2
    when "weeks_2_4"  then ((date.day - 1) / 7).odd?
    else false
    end
  end

  # Monthly target: the synced vcsi_rise SellerTarget for the month, falling
  # back to the sales_target column on the seller master.
  def target_for(month = Date.current.beginning_of_month)
    SellerTarget.find_by(seller: self, period_type: :mtd, period_date: month)&.target_amount ||
      sales_target || 0
  end

  # Confirmed sellout (from vcsi_rise, GIV x 1.12) for the month to date.
  def actual_for(month = Date.current.beginning_of_month)
    SelloutSnapshot.mtd_actual_for(self, month: month)
  end
  alias_method :confirmed_actual, :actual_for

  # "To invoice": value of SFA presell orders taken this month, pending OSB
  # invoicing. A distinct pipeline from vcsi_rise confirmed sellout (mostly
  # non-SFA, can be negative), so NOT reconciled against it. Excludes cancelled.
  def pending_presell(month = Date.current.beginning_of_month)
    orders.where.not(status: :cancelled)
          .where(ordered_at: month.beginning_of_day..month.end_of_month.end_of_day)
          .sum(:total_amount)
  end

  # Reconciling actual shown vs target: confirmed + fresh presell.
  def blended_actual(month = Date.current.beginning_of_month)
    confirmed_actual(month) + pending_presell(month)
  end

  def attainment_pct(month = Date.current.beginning_of_month)
    t = target_for(month)
    t.positive? ? (blended_actual(month) / t * 100).round : nil
  end

end
