# Bulk-loads everything Store#assortment_compliance / #assortment_by_type need
# for MANY stores at once — the applicable assortments, their must-stock items,
# and what each store carried (vcsi confirmed sellout + SFA presell) — in a
# fixed handful of queries. The per-store methods cost ~5 queries each, which
# across thousands of stores ties up a request for minutes.
# Used by Store.assortment_compliance_for / Store.assortment_by_type_for.
class MustStockBatch
  attr_reader :stores, :windows

  def initialize(stores, type_code: nil, on: Date.current, since: nil)
    @stores = stores.to_a
    @windows = {} # reset_months => window start, shared with Store.must_stock_index
    @sellouts = Hash.new { |h, k| h[k] = [] }
    @presell = Hash.new { |h, k| h[k] = [] }
    @cutoffs = {}
    @assortments = []
    @items = {}
    return if @stores.empty?

    @assortments = load_assortments(type_code, on)
    return if @assortments.empty?

    @by_id = @assortments.index_by(&:first)
    @items = AssortmentItem.where(assortment_id: @by_id.keys, must_stock: true).joins(:product)
                           .pluck(:assortment_id, "products.id", "products.it_barcode", "products.case_cost")
                           .group_by(&:first)
    starts = since ? [since] : @assortments.map { |a| @windows[a[6]] ||= Assortment.window_start_for(a[6], on) }
    load_carried(starts.min)
  end

  # Ids of the assortments that apply to the store (nil branch/channel/category
  # on the assortment = wildcard) — same rule as Assortment.resolved_scope_for.
  # Stores with the same key share the same must-stock list.
  def assortment_key(store)
    @assortments.filter_map do |id, b, c, cat|
      id if (b.nil? || b == store.branch_id) && (c.nil? || c == store.channel_id) &&
            (cat.nil? || cat == store.store_category_id)
    end
  end

  # Must-stock rows for an assortment key, in Store#must_stock_raw's shape:
  # [type_code, type_name, reset_months, product_id, barcode, case_cost].
  def raw_for(key)
    key.flat_map do |aid|
      _id, _b, _c, _cat, code, name, reset_m = @by_id[aid]
      (@items[aid] || []).map { |_aid, pid, bc, cc| [code, name, reset_m, pid, bc, cc] }
    end
  end

  # Carried dist keys for the store since `window` — same result as
  # Store#carried_dist_keys(since: window).
  def carried(store, window)
    month = window.to_date.beginning_of_month
    cut_at = @cutoffs[store.id]
    keys = Set.new
    @sellouts[store.id].each { |bc, d| keys << Store.dist_key(bc, nil) if d >= month }
    @presell[store.id].each do |bc, pid, at|
      keys << Store.dist_key(bc, pid) if at >= window && (cut_at.nil? || at > cut_at)
    end
    keys
  end

  private

  def load_assortments(type_code, on)
    scope = Assortment.active_on(on).joins(:assortment_type)
    if type_code.present?
      type = AssortmentType.find_by(code: type_code)
      return [] unless type

      scope = scope.where(assortment_type_id: type.id)
    end
    scope.pluck(:id, :branch_id, :channel_id, :store_category_ref_id,
                "assortment_types.code", "assortment_types.name", :reset_months)
  end

  # Latest confirmed month per store x barcode and latest presell order per
  # store x product, so "carried since w" is just latest >= w.
  def load_carried(earliest)
    ids = @stores.map(&:id)
    StoreSkuSellout.where(store_id: ids).where("pieces > 0").in_window(earliest)
                   .group(:store_id, :it_barcode).maximum(:period_date)
                   .each { |(sid, bc), d| @sellouts[sid] << [bc, d] }
    # Presell only counts after the latest confirmed month. carried_dist_keys
    # binds that Date in SQL, so it compares as midnight UTC against ordered_at.
    StoreSkuSellout.where(store_id: ids).group(:store_id).maximum(:period_date).each do |sid, d|
      cut = d.end_of_month
      @cutoffs[sid] = Time.utc(cut.year, cut.month, cut.day)
    end
    Order.joins(order_lines: :product)
         .where(store_id: ids).where.not(status: :cancelled)
         .where("orders.ordered_at >= ?", earliest)
         .group("orders.store_id", "products.it_barcode", "products.id").maximum(:ordered_at)
         .each { |(sid, bc, pid), at| @presell[sid] << [bc, pid, at] }
  end
end
