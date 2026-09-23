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
    by_store = Hash.new(0.0)
    rows.each do |r|
      bc = r["it_barcode"].to_s
      amt = r["amount"].to_f
      by_bc[bc][:amount] += amt
      by_bc[bc][:pieces] += r["pieces"].to_f
      p = prods[bc]
      by_cat[p&.product_category&.name || "Uncategorized"] += amt
      by_brand[p&.brand&.name || "Other"] += amt
      by_store[r["customer_id"].to_s] += amt
    end

    top_products = by_bc.map do |bc, v|
      p = prods[bc]
      { it_barcode: bc, sku: p&.sku, description: p&.description || bc,
        amount: v[:amount].round(2), pieces: v[:pieces].round }
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
    }
  end

  private

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
    hash.reject { |_k, v| v <= 0 }
        .sort_by { |_k, v| -v }
        .first(limit)
        .map { |name, amount| { name: name, amount: amount.round(2) } }
  end

  def store_rank(by_store, limit = @top)
    names = Store.where(vcsi_customer_ref: by_store.keys).pluck(:vcsi_customer_ref, :name).to_h
    by_store.reject { |_k, v| v <= 0 }
            .sort_by { |_k, v| -v }
            .first(limit)
            .map { |ref, amount| { customer_id: ref, name: names[ref] || ref, amount: amount.round(2) } }
  end
end
