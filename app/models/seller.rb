class Seller < ApplicationRecord
  # Per-seller mobile PIN (bcrypt). Set in the seller master; the app logs in
  # with seller_code + this PIN. `validations: false` so a blank PIN is allowed
  # (falls back to the shared PIN until one is set).
  has_secure_password :pin, validations: false

  belongs_to :branch
  belongs_to :user, optional: true
  has_many :routes, dependent: :nullify
  has_many :stores, dependent: :nullify              # directly-assigned stores
  has_many :route_stores, through: :routes, source: :stores
  has_many :store_registrations, dependent: :nullify

  enum :status, { active: 0, suspended: 1, inactive: 2 }, default: :active

  validates :seller_code, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true

  has_many :seller_targets, dependent: :destroy
  has_many :seller_daily_stats, dependent: :destroy
  has_many :sellout_snapshots, dependent: :destroy
  has_many :sku_sellout_snapshots, dependent: :destroy
  has_many :orders, dependent: :restrict_with_error

  def pin_set?
    pin_digest.present?
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

  # Presell orders booked SINCE the last sellout sync (last_sync_at) — the
  # optimistic top-up that reconciles to invoiced truth on the next sync.
  # Excludes cancelled orders.
  def pending_presell(month = Date.current.beginning_of_month)
    scope = orders.where.not(status: :cancelled)
                  .where(ordered_at: month.beginning_of_day..month.end_of_month.end_of_day)
    scope = scope.where("orders.ordered_at > ?", last_sync_at) if last_sync_at
    scope.sum(:total_amount)
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
