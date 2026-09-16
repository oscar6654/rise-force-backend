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

  # "To invoice": orders placed this month that vcsi_rise hasn't invoiced yet =
  # total ordered − confirmed (invoiced) actual, clamped at 0. This reconciles by
  # AMOUNT rather than by sync time, so a just-placed order stays visible until
  # it's actually invoiced (it doesn't vanish the moment a sync runs).
  def pending_presell(month = Date.current.beginning_of_month)
    ordered = orders.where.not(status: :cancelled)
                    .where(ordered_at: month.beginning_of_day..month.end_of_month.end_of_day)
                    .sum(:total_amount)
    [ordered - confirmed_actual(month), 0].max
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

  # Distribution keys the store is actively carrying within the trailing window.
  # vcsi_rise confirmed (invoiced, net of credit notes/returns) sellout is the
  # source of truth: once a month is confirmed, its carried barcodes come from
  # vcsi — so an order of 20 that invoices to 10, or is returned via CN, shows
  # 10, not the presell 20. SFA presell orders only provisionally fill months
  # vcsi hasn't confirmed yet (so a just-taken order still counts until it is
  # invoiced). No confirmed data at all (endpoint undeployed) => pure presell.
  def carried_dist_keys(since: 90.days.ago)
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

  # { must:, carried:, pct:, gap_product_ids: } or nil if no must-stock defined.
  # Counts by unique barcode; gap_product_ids returns one representative SKU per
  # missing barcode (so the gap list shows one line per product, not per pack).
  def assortment_compliance(since: 90.days.ago, type_code: nil)
    must = must_stock_products(type_code: type_code)
    return nil if must.empty?

    # Highest case_cost first so the first row per barcode group is the same
    # representative the catalog collapses to (the SKU the seller can order).
    by_key = must.sort_by { |id, _bc, cc| [-(cc || 0), id] }
                 .group_by { |id, bc, _cc| dist_key(bc, id) } # key => [[id, bc, cc], ...]
    carried = carried_dist_keys(since: since)
    carried_keys, gap_keys = by_key.keys.partition { |k| carried.include?(k) }
    {
      must: by_key.size, carried: carried_keys.size,
      pct: (carried_keys.size * 100.0 / by_key.size).round,
      gap_product_ids: gap_keys.map { |k| by_key[k].first.first }
    }
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
