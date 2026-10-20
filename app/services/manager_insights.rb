# Deep analytics for the manager app, computed LIVE from vcsi_rise (no local
# persistence) so the numbers always match the ERP and drill per store like
# vcsi_rise. Scope by a set of sales_rep codes (team or seller) and optionally
# one store's customer_id. Barcode → category/brand comes from the SFA product
# master (vcsi returns barcode-level rows).
class ManagerInsights
  def initialize(rep_codes:, customer_id: nil, month: Date.current.beginning_of_month, top: 8)
    @reps = Array(rep_codes).map(&:to_s).reject(&:blank?).uniq
    @cust = customer_id.presence
    @month = month
    @top = top
    @client = VcsiRise::Client.new
  end

  def call
    daily_this = normalize_daily(@client.sales_daily(month: @month, sales_rep: @reps, customer_id: @cust))
    daily_last = normalize_daily(@client.sales_daily(month: @month - 1.month, sales_rep: @reps, customer_id: @cust))

    rows = @client.store_sku_sellout(month: @month, sales_rep: @reps)
    rows = rows.select { |r| r["customer_id"].to_s == @cust.to_s } if @cust
    prods = product_map(rows.map { |r| r["it_barcode"].to_s }.uniq)

    by_bc = Hash.new { |h, k| h[k] = { amount: 0.0, pieces: 0.0 } }
    by_cat = Hash.new(0.0)
    by_brand = Hash.new(0.0)
    rows.each do |r|
      bc = r["it_barcode"].to_s
      amt = r["amount"].to_f
      by_bc[bc][:amount] += amt
      by_bc[bc][:pieces] += r["pieces"].to_f
      p = prods[bc]
      by_cat[p&.product_category&.name || "Uncategorized"] += amt
      by_brand[p&.brand&.name || "Other"] += amt
    end

    # Top stores must NET returns (so they reconcile to the headline total), so
    # build them from the per-store sellout feed rather than the per-SKU rows,
    # which drop negative-net barcodes. Skipped for a single-store scope. The
    # raw rows are reused for the per-channel breakdown so we don't re-fetch.
    store_rows = @cust ? [] : @client.store_sellout(month: @month, sales_rep: @reps)
    by_store = store_rows.each_with_object(Hash.new(0.0)) { |r, h| h[r["customer_id"].to_s] += r["sellout"].to_f }

    prod_total = by_bc.values.sum { |v| v[:amount] }
    top_products = by_bc.map do |bc, v|
      p = prods[bc]
      ppc = p&.pcs_per_case.to_i
      { it_barcode: bc, sku: p&.sku, description: p&.description || bc,
        amount: v[:amount].round(2), pieces: v[:pieces].round,
        # Amount in cases (pieces ÷ pack size); nil when the pack size is unknown.
        cases: (ppc.positive? ? (v[:pieces] / ppc).round(1) : nil),
        # Salience: this SKU's share of total product sellout, as a percent.
        share: share_of(v[:amount], prod_total) }
    end.sort_by { |x| -x[:amount] }.first(@top)

    {
      period: @month.strftime("%Y-%m"),
      # Headline total must NET returns to match the ERP: the daily feed sums
      # GIV*1.12 over every line (CN lines are negative), whereas the per-SKU
      # rows below drop negative-net barcodes (a "carried?" rule) and so would
      # over-report sellout by the value of those hidden returns. Fall back to
      # the per-SKU sum only if the daily feed is unavailable (undeployed).
      confirmed_total: (daily_this.any? ? daily_this.sum { |d| d[:amount] } : by_bc.values.sum { |v| v[:amount] }).round(2),
      daily: { this_month: daily_this, last_month: daily_last },
      top_products: top_products,
      by_category: rank(by_cat),
      by_brand: rank(by_brand),
      by_store: @cust ? [] : store_rank(by_store),
      by_channel: @cust ? [] : by_channel(store_rows),
    }
  end

  private

  # Per-channel execution for the scope's stores (HFS SMALL, HFS WHOLESALE, …):
  # sellout MTD + MoM/YoY growth from vcsi_rise, plus active-store count and
  # must-stock distribution % from the local masters. `cur_rows` is the current
  # month's store_sellout feed (reused from #call so we don't re-fetch it).
  def by_channel(cur_rows)
    last_rows = @client.store_sellout(month: @month - 1.month, sales_rep: @reps)
    ya_rows   = @client.store_sellout(month: @month - 12.months, sales_rep: @reps)

    # Everything is keyed off the FEED's customer_ids (the vcsi store identity),
    # never the master's seller→store assignment: a store can be reassigned to a
    # different seller over time, be newer than a year (no year-ago row), or have
    # closed, so only the customer_id is stable across the comparison window. The
    # channel + assortment come from the store master, joined on vcsi_customer_ref.
    refs     = (cur_rows + last_rows + ya_rows).map { |r| r["customer_id"].to_s }.uniq
    stores   = Store.where(vcsi_customer_ref: refs).includes(:channel)
    chan_of  = {} # customer_ref => channel_id
    store_of = {} # customer_ref => Store (for distribution)
    stores.each do |s|
      chan_of[s.vcsi_customer_ref.to_s]  = s.channel_id
      store_of[s.vcsi_customer_ref.to_s] = s
    end

    sell_now  = channel_sums(cur_rows,  chan_of)
    sell_last = channel_sums(last_rows, chan_of)
    sell_ya   = channel_sums(ya_rows,   chan_of)

    # Active = a store that actually sold in the month. This vs same-month-last-
    # year shows real coverage change (new doors open, closed doors drop out).
    active_now = channel_active(cur_rows, chan_of)
    active_ya  = channel_active(ya_rows,  chan_of)

    # Distribution = avg must-stock compliance across the stores that SOLD this
    # month in the channel (current assortment execution for stores we service).
    cur_stores = cur_rows.filter_map { |r| store_of[r["customer_id"].to_s] }.uniq
    comp       = cur_stores.any? ? Store.assortment_compliance_for(cur_stores) : {}
    pcts_of    = Hash.new { |h, k| h[k] = [] }
    cur_stores.each { |s| (p = comp[s.id]&.dig(:pct)) && pcts_of[s.channel_id] << p }

    names = Channel.pluck(:id, :name).to_h
    total = sell_now.values.sum
    (sell_now.keys | active_now.keys).map do |cid|
      now  = sell_now[cid].to_f
      pcts = pcts_of[cid]
      { channel_id: cid, name: names[cid] || "No channel",
        sellout: now.round(2), share: share_of(now, total),
        mom: growth(now, sell_last[cid]), yoy: growth(now, sell_ya[cid]),
        active_stores: active_now[cid].to_i, active_stores_ya: active_ya[cid].to_i,
        distribution_pct: pcts.any? ? (pcts.sum.to_f / pcts.size).round : nil }
    end.reject { |c| c[:sellout].zero? && c[:active_stores].zero? }
       .sort_by { |c| -c[:sellout] }
  end

  # Sum a store_sellout feed into { channel_id => sellout } via the ref→channel map.
  def channel_sums(rows, chan_of)
    Array(rows).each_with_object(Hash.new(0.0)) do |r, h|
      ref = r["customer_id"].to_s
      h[chan_of[ref]] += r["sellout"].to_f if chan_of.key?(ref)
    end
  end

  # Count distinct stores that sold (sellout > 0) per channel in a feed.
  def channel_active(rows, chan_of)
    seen = Hash.new { |h, k| h[k] = Set.new }
    Array(rows).each do |r|
      ref = r["customer_id"].to_s
      seen[chan_of[ref]] << ref if chan_of.key?(ref) && r["sellout"].to_f.positive?
    end
    seen.transform_values(&:size)
  end

  # Percent change vs a base, or nil when there's no comparable base (so the app
  # shows "—" rather than a misleading +100%/∞).
  def growth(now, base)
    base.to_f.positive? ? ((now - base) / base * 100).round(1) : nil
  end

  def normalize_daily(data)
    Array(data).filter_map do |r|
      d = r["date"].presence
      next unless d

      { date: d, amount: r["amount"].to_f.round(2), pieces: r["pieces"].to_f.round }
    end.sort_by { |x| x[:date] }
  end

  # barcode => representative Product (highest case_cost), with category+brand.
  def product_map(barcodes)
    return {} if barcodes.empty?

    Product.where(it_barcode: barcodes).includes(:product_category, :brand)
           .group_by(&:it_barcode)
           .transform_values { |ps| ps.max_by { |p| p.case_cost.to_f } }
  end

  def rank(hash, limit = @top)
    total = hash.each_value.select(&:positive?).sum
    hash.reject { |_k, v| v <= 0 }
        .sort_by { |_k, v| -v }
        .first(limit)
        .map { |name, amount| { name: name, amount: amount.round(2), share: share_of(amount, total) } }
  end

  def store_rank(by_store, limit = @top)
    total = by_store.each_value.select(&:positive?).sum
    names = Store.where(vcsi_customer_ref: by_store.keys).pluck(:vcsi_customer_ref, :name).to_h
    by_store.reject { |_k, v| v <= 0 }
            .sort_by { |_k, v| -v }
            .first(limit)
            .map { |ref, amount| { customer_id: ref, name: names[ref] || ref, amount: amount.round(2), share: share_of(amount, total) } }
  end

  # Percent share of a dimension total (salience), 0.0 when the total is zero.
  def share_of(amount, total)
    total.to_f.positive? ? (amount / total * 100).round(1) : 0.0
  end
end
