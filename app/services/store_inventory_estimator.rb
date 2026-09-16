# Estimates each SKU's CURRENT shelf inventory and the ideal case order (ICO)
# for a store from its stock-check history + vcsi confirmed deliveries. This is
# the "sell-more from what's actually on the shelf" brain behind the order
# screen's "From stock check" tab and the console stock report.
#
# Per product (collapsed to the barcode representative the seller orders):
#   • Anchor         = the store's most recent stock count (on-hand pieces @ date)
#   • Deliveries     = vcsi confirmed sellout pieces (store_sku_sellouts, monthly),
#                      prorated by day — the distributor's invoices INTO the store
#   • Offtake/day    = consumption inferred between the two most recent counts:
#                        (qty0 + delivered_in_window − qty1), clamped ≥ 0, ÷ days;
#                      falls back to a delivery proxy (recent month ÷ 30) when
#                      there's only one count so far
#   • Predicted now  = anchor + delivered_since_anchor − offtake × days_since
#   • Cover target   = days to the next scheduled visit + safety buffer
#   • ICO pieces     = max(0, offtake × cover − predicted − in_transit)
#                      (in_transit = pieces already on an un-invoiced SFA order)
#
# Deliveries are monthly (that's the vcsi grain), so windows are day-prorated —
# an approximation, documented here and clamped so noise can't push a negative.
class StoreInventoryEstimator
  DEFAULT_SAFETY_DAYS = 3

  Row = Struct.new(:product_id, :sku, :description, :it_barcode, :pcs_per_case,
                   :on_hand, :checked_on, :days_since_check, :delivered_since,
                   :offtake_per_day, :predicted_on_hand, :cover_days,
                   :suggested_pieces, :suggested_cases, :basis, keyword_init: true)

  def initialize(store, today: Date.current)
    @store = store
    @today = today
    @safety = SystemSetting.get("ico_safety_days", DEFAULT_SAFETY_DAYS).to_i
  end

  def next_visit_on
    (1..60).each { |i| d = @today + i; return d if @store.due_on?(d) }
    nil
  end

  def last_checked_on
    stock_series.values.filter_map { |pts| pts.last&.first }.max
  end

  def rows
    series = stock_series
    return [] if series.empty?

    deliveries = monthly_deliveries
    transit = in_transit_pieces
    cover = cover_days

    series.filter_map do |pid, points|
      rep = representative(pid)
      next unless rep

      per = rep.pcs_per_case.to_i
      per = 1 if per <= 0
      bc = rep.it_barcode.to_s.strip
      last_on, on_hand_bd = points.last
      on_hand = on_hand_bd.to_f
      days_since = (@today - last_on).to_i.clamp(0, 3650)

      delivered_since = delivered_between(deliveries[bc], last_on, @today).to_f
      rate = offtake_rate(points, deliveries[bc])
      basis = "offtake"
      if rate.nil?
        rate = delivery_proxy_rate(deliveries[bc])
        basis = rate ? "delivery" : "none"
      end

      predicted = [on_hand + delivered_since - (rate ? rate * days_since : 0.0), 0.0].max
      pieces = rate ? [(rate * cover - predicted - (transit[rep.id] || 0).to_f).round, 0].max : 0

      Row.new(
        product_id: rep.id, sku: rep.sku, description: rep.description, it_barcode: rep.it_barcode,
        pcs_per_case: per, on_hand: on_hand.round, checked_on: last_on,
        days_since_check: days_since, delivered_since: delivered_since.round,
        offtake_per_day: rate&.round(2), predicted_on_hand: predicted.round,
        cover_days: cover, suggested_pieces: pieces, suggested_cases: (pieces.to_f / per).round,
        basis: basis
      )
    end
  end

  # Sell-through analytics over a date range: per SKU, total sold (offtake),
  # delivered, and average daily offtake across the counts inside [from, to].
  # Needs ≥2 counts in the window for a SKU to have a rate.
  OfftakeRow = Struct.new(:product_id, :sku, :description, :it_barcode, :counts,
                          :first_count_on, :last_count_on, :delivered, :sold,
                          :days, :avg_daily, keyword_init: true)

  def offtake_analysis(from: nil, to: nil)
    deliveries = monthly_deliveries
    stock_series.filter_map do |pid, all_points|
      points = all_points.select { |d, _| (from.nil? || d >= from) && (to.nil? || d <= to) }
      next if points.size < 2

      rep = representative(pid)
      next unless rep

      bc = rep.it_barcode.to_s.strip
      sold = 0.0
      delivered = 0.0
      days = 0
      points.each_cons(2) do |(d0, q0), (d1, q1)|
        gap = (d1 - d0).to_i
        next if gap <= 0

        del = delivered_between(deliveries[bc], d0, d1).to_f
        consumed = q0.to_f + del - q1.to_f
        consumed = 0.0 if consumed.negative?
        sold += consumed
        delivered += del
        days += gap
      end
      next if days <= 0

      OfftakeRow.new(product_id: rep.id, sku: rep.sku, description: rep.description, it_barcode: rep.it_barcode,
                     counts: points.size, first_count_on: points.first.first, last_count_on: points.last.first,
                     delivered: delivered.round, sold: sold.round, days: days, avg_daily: (sold / days).round(2))
    end.sort_by { |r| -r.sold }
  end

  private

  # product_id => [[date, pieces], ...] ascending; same-day recount keeps the last.
  def stock_series
    grouped = Hash.new { |h, k| h[k] = {} }
    StockCount.joins(:visit)
              .where(visits: { store_id: @store.id })
              .order(Arel.sql("COALESCE(visits.visit_date, stock_counts.created_at::date) ASC"))
              .pluck("stock_counts.product_id",
                     Arel.sql("COALESCE(visits.visit_date, stock_counts.created_at::date)"),
                     "stock_counts.qty")
              .each { |pid, date, qty| grouped[pid][date.to_date] = qty.to_d }
    grouped.transform_values { |m| m.sort_by(&:first) }
  end

  # barcode => { month_start_date => delivered_pieces } (vcsi confirmed, monthly).
  def monthly_deliveries
    out = Hash.new { |h, k| h[k] = {} }
    @store.store_sku_sellouts.where("pieces > 0")
          .pluck(:it_barcode, :period_date, :pieces)
          .each { |bc, pd, pcs| out[bc.to_s.strip][pd.to_date.beginning_of_month] = pcs.to_d }
    out
  end

  # Day-prorated deliveries whose calendar month overlaps [from, to].
  def delivered_between(month_map, from_date, to_date)
    return 0.to_d if month_map.nil? || month_map.empty? || to_date < from_date

    month_map.sum(0.to_d) do |month, pieces|
      m_start = month.beginning_of_month
      m_end = month.end_of_month
      lo = [from_date, m_start].max
      hi = [to_date, m_end].min
      next 0.to_d if hi < lo

      days_in_month = (m_end - m_start).to_i + 1
      overlap = (hi - lo).to_i + 1
      pieces * overlap / days_in_month
    end
  end

  # Consumption/day between the two most recent counts, delivery-adjusted.
  def offtake_rate(points, month_map)
    return nil if points.size < 2

    (d0, q0), (d1, q1) = points[-2], points[-1]
    days = (d1 - d0).to_i
    return nil if days <= 0

    consumed = q0.to_f + delivered_between(month_map, d0, d1).to_f - q1.to_f
    consumed = 0.0 if consumed.negative?
    consumed / days
  end

  # Steady-state proxy when there's only one count: recent month delivered ÷ 30.
  def delivery_proxy_rate(month_map)
    return nil if month_map.nil? || month_map.empty?

    recent = month_map.max_by(&:first)&.last.to_f
    recent.positive? ? recent / 30.0 : nil
  end

  def cover_days
    base = (nxt = next_visit_on) ? (nxt - @today).to_i : (@store.freq_f4? ? 7 : 14)
    [base, 1].max + @safety
  end

  # rep_product_id => pieces already ordered (SFA) but not yet invoiced.
  def in_transit_pieces
    h = Hash.new(0.to_d)
    OrderLine.joins(:order).includes(:product)
             .where(orders: { store_id: @store.id, status: %i[submitted batched downloaded] })
             .find_each do |l|
      p = l.product
      next unless p

      rep = (p.it_barcode.present? && Product.representative_for(p.it_barcode)) || p
      per = p.pcs_per_case.to_i
      per = 1 if per <= 0
      h[rep.id] += l.uom.to_s.include?("case") ? l.quantity * per : l.quantity
    end
    h
  end

  def representative(pid)
    p = Product.find_by(id: pid)
    return nil unless p

    (p.it_barcode.present? && Product.representative_for(p.it_barcode)) || p
  end
end
