class Store < ApplicationRecord
  belongs_to :branch
  belongs_to :channel, optional: true
  belongs_to :route, optional: true
  belongs_to :seller, optional: true # direct sales-rep assignment (vcsi customer.sales_rep)
  belongs_to :store_category, optional: true # flexible, managed master (drives pricing)
  belongs_to :store_registration, optional: true

  has_many :orders, dependent: :restrict_with_error
  has_many :store_sku_sellouts, dependent: :delete_all
  has_many :store_targets, dependent: :destroy
  has_many :sellout_snapshots, dependent: :nullify

  attr_writer :category_code

  enum :status, { provisional: 0, active: 1, inactive: 2, closed: 3, rejected: 4 }, default: :active
  enum :visit_frequency, { f2: 2, f4: 4 }, prefix: :freq
  enum :week_pattern, { every_week: 0, weeks_1_3: 1, weeks_2_4: 2 }
  enum :visit_day, { mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 }, allow_nil: true

  validates :name, presence: true
  validate :has_a_code

  before_validation :resolve_category_code
  before_validation :normalize_week_pattern

  scope :for_branches, ->(ids) { where(branch_id: ids) }

  # "Active" = actually buying, i.e. has invoiced sellout in vcsi_rise this
  # period (the source of truth), NOT merely status: :active in the master.
  scope :active_in_vcsi, ->(month = Date.current.beginning_of_month) {
    where(id: SelloutSnapshot.where(seller_id: nil, product_id: nil,
                                    period_type: :mtd, period_date: month)
                             .where("amount > 0").select(:store_id))
  }

  def active_in_vcsi?(month = Date.current.beginning_of_month)
    SelloutSnapshot.store_mtd_actual_for(self, month: month).to_d.positive?
  end
  scope :search, ->(q) {
    return all if q.blank?
    where("name ILIKE :q OR store_code ILIKE :q OR owner_name ILIKE :q", q: "%#{sanitize_sql_like(q)}%")
  }

  # The seller responsible for this store: a direct assignment wins, else the
  # store's route's seller.
  def assigned_seller
    seller || route&.seller
  end

  # ---- Actual vs target (vcsi_rise is the source of truth) -----------------
  # Derived monthly target: trailing avg of vcsi_rise history + growth uplift.
  def target_for(month = Date.current.beginning_of_month)
    StoreTarget.for_month(month).find_by(store: self)&.target_amount || 0
  end

  # Invoiced truth from vcsi_rise, as of the last sellout sync.
  def confirmed_actual(month = Date.current.beginning_of_month)
    SelloutSnapshot.store_mtd_actual_for(self, month: month)
  end

  # "To invoice": the value of SFA presell orders taken this month, pending OSB
  # invoicing. This is a DISTINCT pipeline from vcsi_rise confirmed sellout (which
  # is mostly non-SFA DMS sales and can even go negative from credit notes), so it
  # is NOT reconciled against confirmed — it simply reflects what the seller
  # ordered. Excludes cancelled orders; resets each month.
  def pending_presell(month = Date.current.beginning_of_month)
    orders.where.not(status: :cancelled)
          .where(ordered_at: month.beginning_of_day..month.end_of_month.end_of_day)
          .sum(:total_amount)
  end

  # The reconciling actual shown against target: confirmed truth + fresh presell
  # the sync hasn't caught up with yet. Before any sync, this is all presell.
  def blended_actual(month = Date.current.beginning_of_month)
    confirmed_actual(month) + pending_presell(month)
  end

  def attainment_pct(month = Date.current.beginning_of_month)
    t = target_for(month)
    t.positive? ? (blended_actual(month) / t * 100).round : nil
  end

  # ---- Must-carry (assortment) compliance ----------------------------------
  # Distribution is measured by unique PRODUCT (it_barcode), not item_key: many
  # item_keys (pack sizes / variants) share one barcode and count as a single
  # distribution point. A SKU with no barcode counts on its own.
  def dist_key(barcode, product_id)
    barcode.present? ? "b:#{barcode.strip}" : "p:#{product_id}"
  end

  # Must-stock products resolved for this store, as [product_id, it_barcode,
  # case_cost] rows (unique per product). `type_code` restricts to one
  # assortment type (nil = all types merged). case_cost is carried so the
  # barcode representative matches the catalog's (highest cost = highest price).
  def must_stock_products(type_code: nil)
    Assortment.resolved_items_for(self, type_code: type_code).where(must_stock: true)
              .joins(:product).pluck("products.id", "products.it_barcode", "products.case_cost")
              .uniq { |id, _bc, _cc| id }
  end

  # Start of the distribution/assortment "carried" window. Distribution and
  # assortment-type metrics RESET MONTHLY by default — carried counts only what
  # sold (vcsi confirmed) or was ordered (presell) within `month`, so a new
  # month starts fresh and builds up as the route is worked. Set SystemSetting
  # `assortment_window_mode` to "trailing" to use a rolling window of
  # `assortment_window_days` (default 90) instead.
  def self.dist_window_start(month = Date.current.beginning_of_month)
    if SystemSetting.get("assortment_window_mode", "monthly").to_s == "trailing"
      (Time.current - SystemSetting.get("assortment_window_days", 90).to_i.days)
    else
      # Zone-aware local midnight so the presell `ordered_at` (UTC) comparison
      # doesn't drop orders placed just after midnight in the branch timezone.
      month.to_date.beginning_of_month.in_time_zone
    end
  end

  # Distribution keys the store is actively carrying within the window (monthly
  # reset by default — see .dist_window_start).
  # vcsi_rise confirmed (invoiced, net of credit notes/returns) sellout is the
  # source of truth: once a month is confirmed, its carried barcodes come from
  # vcsi — so an order of 20 that invoices to 10, or is returned via CN, shows
  # 10, not the presell 20. SFA presell orders only provisionally fill months
  # vcsi hasn't confirmed yet (so a just-taken order still counts until it is
  # invoiced). No confirmed data at all (endpoint undeployed) => pure presell.
  def carried_dist_keys(since: Store.dist_window_start)
    keys = Set.new

    confirmed = store_sku_sellouts.in_window(since).where("pieces > 0")
    confirmed.distinct.pluck(:it_barcode).each { |bc| keys << dist_key(bc, nil) }

    # Presell counts only for activity newer than the latest confirmed month;
    # older presell is superseded by the vcsi truth above.
    cutoff = store_sku_sellouts.maximum(:period_date)&.end_of_month
    presell = orders.where.not(status: :cancelled).where("ordered_at >= ?", since)
    presell = presell.where("ordered_at > ?", cutoff) if cutoff
    OrderLine.where(order_id: presell.select(:id)).joins(:product)
             .distinct.pluck("products.it_barcode", "products.id")
             .each { |bc, pid| keys << dist_key(bc, pid) }

    keys
  end

  # Must-stock rows tagged with their assortment's reset window:
  # [type_code, type_name, reset_months, product_id, barcode, case_cost].
  def must_stock_raw(type_code: nil, on: Date.current)
    Assortment.resolved_scope_for(self, on: on, type_code: type_code)
              .joins(:assortment_type)
              .joins(assortment_items: :product)
              .where(assortment_items: { must_stock: true })
              .pluck("assortment_types.code", "assortment_types.name", "assortments.reset_months",
                     "products.id", "products.it_barcode", "products.case_cost")
  end

  # { must:, carried:, pct:, gap_product_ids: } or nil if no must-stock defined.
  # Each must-stock barcode is checked against ITS assortment's reset window
  # (monthly / quarterly / half-year), so a quarterly target counts a SKU carried
  # anytime in the quarter. Pass `since:` to force a single window (legacy).
  def assortment_compliance(type_code: nil, on: Date.current, since: nil)
    raw = must_stock_raw(type_code: type_code, on: on)
    return nil if raw.empty?

    # Dedupe by distribution key (barcode); representative = highest case_cost;
    # window = earliest start among contributing assortments (most lenient).
    by_key = {}
    raw.each do |_code, _name, reset_m, pid, bc, cc|
      key = dist_key(bc, pid)
      w = since || Assortment.window_start_for(reset_m, on)
      g = (by_key[key] ||= { rep_id: pid, rep_cc: cc.to_f, window: w })
      if cc.to_f > g[:rep_cc]
        g[:rep_id] = pid
        g[:rep_cc] = cc.to_f
      end
      g[:window] = w if w < g[:window]
    end

    carried_cache = {}
    carried_count = 0
    gap_ids = []
    by_key.each do |key, g|
      set = (carried_cache[g[:window]] ||= carried_dist_keys(since: g[:window]))
      set.include?(key) ? (carried_count += 1) : (gap_ids << g[:rep_id])
    end
    { must: by_key.size, carried: carried_count,
      pct: (carried_count * 100.0 / by_key.size).round, gap_product_ids: gap_ids }
  end

  # Per-assortment-type compliance for this store. Carried is computed per
  # distinct reset window, so types/assortments on different cycles are correct.
  # Returns [{ type_code, type_name, must, carried, pct }] for types with must-stock.
  def assortment_by_type(on: Date.current, since: nil)
    raw = must_stock_raw(on: on)
    return [] if raw.empty?

    types = {} # code => { keys: { dist_key => earliest window } }
    raw.each do |code, _name, reset_m, pid, bc, _cc|
      key = dist_key(bc, pid)
      w = since || Assortment.window_start_for(reset_m, on)
      keys = (types[code] ||= {})
      cur = keys[key]
      keys[key] = cur && cur < w ? cur : w
    end

    carried_cache = {}
    AssortmentType.enabled.ordered.filter_map do |t|
      keys = types[t.code]
      next if keys.blank?

      carried = keys.count { |key, w| (carried_cache[w] ||= carried_dist_keys(since: w)).include?(key) }
      { type_code: t.code, type_name: t.name, must: keys.size, carried: carried,
        pct: (carried * 100.0 / keys.size).round }
    end
  end

  def category
    store_category&.code
  end

  def category_letter
    store_category&.letter
  end

  def code
    store_code.presence || provisional_code
  end

  # Is this store scheduled on the given date, per its frequency rule?
  # Week-of-month is computed in the branch timezone.
  def due_on?(date)
    return false if visit_day.nil?
    # visit_days maps mon:1..sat:6; Ruby's Date#wday is 0=Sun..6=Sat, so
    # Mon..Sat line up directly and Sunday (0) never matches.
    return false unless Store.visit_days[visit_day] == date.wday

    case week_pattern
    when "every_week" then true
    when "weeks_1_3"  then week_of_month(date).odd?
    when "weeks_2_4"  then week_of_month(date).even?
    else false
    end
  end

  # 1-based week of month: days 1-7 => 1, 8-14 => 2, ...
  def week_of_month(date)
    ((date.day - 1) / 7) + 1
  end

  private

  def resolve_category_code
    return if @category_code.blank?

    self.store_category = StoreCategory.find_or_create_by_code(@category_code)
  end

  # F4 (weekly) can only be every_week; F2 must be fortnightly. Auto-correct so
  # an invalid combination can't slip past the client-side guard.
  def normalize_week_pattern
    if freq_f4?
      self.week_pattern = :every_week
    elsif freq_f2? && week_pattern == "every_week"
      self.week_pattern = :weeks_1_3
    end
  end

  def has_a_code
    return if store_code.present? || provisional_code.present?

    errors.add(:base, "must have a store code or provisional code")
  end
end
