# Turns the SFA + vcsi_rise data into *actions* for the seller: which stores to
# push today and why, what to cross-sell from what nearby peers are buying, and
# a smart-start order from recent history. This is the "sell more" brain behind
# the app's Today-route priorities and the store-profile recommendations.
class SellerIntelligence
  RECENT_DAYS = 90
  PEER_RADIUS_KM = 5.0

  def initialize(seller, month: Date.current.beginning_of_month)
    @seller = seller
    @month = month
  end

  # ---- Priorities: which stores need attention, ranked, with reasons --------
  # Signals (all from our backend, which mirrors vcsi_rise actuals + history):
  #   - behind month-pace on target (weighted by peso upside)
  #   - missing must-stock SKUs (distribution gaps)
  #   - no order recently (slipping coverage)
  #   - running below its own trailing-3mo average (declining)
  # `store_ids` restricts the candidate set (e.g. to today's planned route), so
  # "Focus today" is empty on a day with no route rather than surfacing stores
  # that aren't due.
  def priorities(limit: 12, store_ids: nil)
    stores = seller_stores.to_a
    stores = stores.select { |s| store_ids.include?(s.id) } if store_ids
    return [] if stores.empty?

    ids = stores.map(&:id)
    targets = StoreTarget.for_month(@month).where(store_id: ids).index_by(&:store_id)
    confirmed = sellout_scope(ids).group(:store_id).sum(:amount)
    presell = Order.where(store_id: ids).where.not(status: :cancelled)
                   .where(ordered_at: @month.beginning_of_day..@month.end_of_month.end_of_day)
                   .group(:store_id).sum(:total_amount)
    last_order = Order.where(store_id: ids).where.not(status: :cancelled)
                      .group(:store_id).maximum(:ordered_at)

    frac = month_elapsed_fraction
    scored = stores.map do |store|
      t = targets[store.id]
      target = t&.target_amount.to_d
      basis = t&.basis_amount.to_d # trailing-3mo avg
      actual = (confirmed[store.id] || 0).to_d + (presell[store.id] || 0).to_d
      reasons = []
      score = 0.0
      upside = 0.to_d

      # Behind pace -> the biggest lever, weighted by peso gap.
      if target.positive?
        expected = (target * frac)
        gap = expected - actual
        if gap > 0
          upside = (target - actual).round
          reasons << { code: 'behind_pace', text: "#{peso(gap)} behind pace", amount: gap.round }
          score += 3.0 + Math.log10([gap.to_f, 1].max)
        end
      end

      # Declining vs its own history.
      if basis.positive? && frac > 0.25
        run_rate = actual / frac
        if run_rate < basis * 0.8
          reasons << { code: 'declining', text: "Down vs 3-mo avg (#{peso(basis)})" }
          score += 2.0
        end
      end

      # No order recently.
      lo = last_order[store.id]
      days = lo ? ((Time.current - lo) / 1.day).floor : nil
      if days.nil? || days > 14
        reasons << { code: 'overdue', text: lo ? "No order in #{days}d" : 'No order yet' }
        score += 1.5
      end

      { store: store, score: score.round(2), upside: upside, reasons: reasons }
    end

    # Must-stock gaps only for the top candidates (assortment resolution is the
    # expensive per-store bit) — bounds the query cost.
    ranked = scored.select { |s| s[:reasons].any? }.sort_by { |s| -s[:score] }.first(limit)
    ranked.each do |row|
      gaps = row[:store].assortment_compliance
      next unless gaps && gaps[:carried] < gaps[:must]

      missing = gaps[:must] - gaps[:carried]
      row[:reasons].unshift({ code: 'must_stock', text: "#{missing} must-stock SKU#{missing > 1 ? 's' : ''} missing" })
      row[:score] += 1.0 + missing * 0.2
    end
    ranked.sort_by { |s| -s[:score] }
  end

  # ---- Cross-sell: "stores like this one nearby are selling X" ---------------
  # Peers = same channel, within PEER_RADIUS_KM, excluding this store. Recommend
  # SKUs the peers order that THIS store isn't ordering. Ranked by how many
  # peers carry it (breadth = a safe, provable pitch).
  def cross_sell(store, limit: 6)
    return [] unless store.latitude && store.longitude

    peers = nearby_peer_ids(store)
    return [] if peers.empty?

    mine = Order.where(store: store).where.not(status: :cancelled)
                .where('ordered_at >= ?', RECENT_DAYS.days.ago)
                .joins(:order_lines).distinct.pluck('order_lines.product_id')

    rows = OrderLine
           .joins(:order)
           .where(orders: { store_id: peers, status: %i[submitted batched downloaded invoiced] })
           .where('orders.ordered_at >= ?', RECENT_DAYS.days.ago)
           .where.not(product_id: mine.presence || [-1])
           .group(:product_id)
           .select('product_id, COUNT(DISTINCT orders.store_id) AS peer_stores, SUM(order_lines.quantity) AS qty')
           .order('peer_stores DESC, qty DESC')
           .limit(limit)

    products = Product.where(id: rows.map(&:product_id)).index_by(&:id)
    rows.filter_map do |r|
      p = products[r.product_id]
      next unless p

      {
        product_id: p.id, sku: p.sku, description: p.description,
        peer_stores: r.peer_stores.to_i,
        reason: "#{r.peer_stores} nearby #{store.channel&.name || 'store'}#{r.peer_stores > 1 ? 's' : ''} carry this",
      }
    end
  end

  # ---- Nearby whitespace: what the NEAREST stores carry that this one lacks --
  # Unlike cross_sell (same-channel peers), peers here are simply the
  # geographically NEAREST stores of ANY channel/type — the visited store may be
  # a big account while its neighbours are small sari-sari, and we still want to
  # know what moves around it. "Carried" is barcode-level (the distribution unit)
  # from vcsi confirmed sellout OR an SFA order within the window; ranked by how
  # many nearby stores carry a barcode this store doesn't. Live, but bounded to
  # the nearest `peers` stores so the query stays cheap.
  NEARBY_RADIUS_KM = 5.0
  NEARBY_PEERS = 40
  WHITESPACE_DAYS = 60

  def nearby_whitespace(store, limit: 12, peers: NEARBY_PEERS, window_days: WHITESPACE_DAYS)
    return [] unless store.latitude && store.longitude

    peer_ids = nearest_store_ids(store, peers)
    return [] if peer_ids.empty?

    since = window_days.days.ago
    carried = Hash.new { |h, k| h[k] = Set.new } # barcode => set of nearby store_ids

    StoreSkuSellout.where(store_id: peer_ids).in_window(since).where("pieces > 0")
                   .distinct.pluck(:store_id, :it_barcode)
                   .each { |sid, bc| carried[bc.to_s.strip] << sid if bc.present? }
    OrderLine.joins(:order, :product)
             .where(orders: { store_id: peer_ids, status: %i[submitted batched downloaded invoiced] })
             .where("orders.ordered_at >= ?", since)
             .distinct.pluck("orders.store_id", "products.it_barcode")
             .each { |sid, bc| carried[bc.to_s.strip] << sid if bc.present? }

    mine = store_carried_barcodes(store, since)
    ranked = carried.reject { |bc, _sids| bc.blank? || mine.include?(bc) }
                    .sort_by { |_bc, sids| -sids.size }
                    .first(limit)

    ranked.filter_map do |bc, sids|
      p = Product.representative_for(bc)
      next unless p

      { product_id: p.id, sku: p.sku, description: p.description,
        peer_stores: sids.size,
        reason: "#{sids.size} nearby store#{sids.size > 1 ? 's' : ''} carry this — you don't" }
    end
  end

  # ---- Next best action: the single highest-value thing to do here ----------
  # Composes pace gap + must-stock + cross-sell + live promos into a ranked,
  # human action list so the seller doesn't have to work it out.
  def next_best_action(store)
    actions = []
    month = @month

    target = store.target_for(month).to_d
    if target.positive?
      gap = target - store.blended_actual(month)
      actions << { code: 'pace', text: "Push #{peso(gap)} to hit target", weight: 3 + Math.log10([gap.to_f, 1].max) } if gap > 0
    end

    comp = store.assortment_compliance
    if comp && comp[:carried] < comp[:must]
      missing = comp[:must] - comp[:carried]
      actions << { code: 'must_stock', text: "Add #{missing} must-stock SKU#{missing > 1 ? 's' : ''}", weight: 2.5 + missing * 0.2 }
    end

    cs = cross_sell(store, limit: 1).first
    actions << { code: 'cross_sell', text: "Introduce #{cs[:description]} — #{cs[:reason]}", weight: 2 } if cs

    promo = Promo.live_on(Date.current).eligible_for(store).find { |p| p.available_for?(store) }
    actions << { code: 'promo', text: "Pitch promo: #{promo.name}", weight: 1.5 } if promo

    ranked = actions.sort_by { |a| -a[:weight] }
    { headline: ranked.first&.dig(:text), actions: ranked.first(3).map { |a| a.slice(:code, :text) } }
  end

  # ---- Predictive reorder: what's likely due, from order cadence -------------
  # For products the store orders regularly, estimate the next-due date from the
  # average interval; flag anything past due with a suggested quantity.
  def predictive_reorder(store, limit: 6)
    orders = Order.where(store: store).where.not(status: :cancelled)
                  .order(:ordered_at).includes(order_lines: :product)
    return [] if orders.size < 2

    by_product = Hash.new { |h, k| h[k] = { dates: [], qtys: [], product: nil, uom: 'case_uom' } }
    orders.each do |o|
      o.order_lines.each do |l|
        cell = by_product[l.product_id]
        cell[:dates] << o.ordered_at.to_date
        cell[:qtys] << l.quantity
        cell[:product] = l.product
        cell[:uom] = l.uom
      end
    end

    due = by_product.filter_map do |pid, c|
      next if c[:dates].size < 2 || c[:product].nil?

      intervals = c[:dates].each_cons(2).map { |a, b| (b - a).to_i }.reject(&:zero?)
      next if intervals.empty?

      avg_interval = intervals.sum / intervals.size.to_f
      days_since = (Date.current - c[:dates].last).to_i
      next if days_since < avg_interval * 0.85 # not due yet

      {
        product_id: pid, sku: c[:product].sku, description: c[:product].description,
        suggested_qty: (c[:qtys].sum / c[:qtys].size).ceil, uom: c[:uom],
        days_since: days_since, avg_interval: avg_interval.round,
        overdue: days_since > avg_interval,
      }
    end
    due.sort_by { |r| -(r[:days_since] - r[:avg_interval]) }.first(limit)
  end

  # ---- Smart-start: prefilled order from the store's recent baskets ----------
  def suggested_order(store, lookback: 3)
    orders = Order.where(store: store).where.not(status: :cancelled)
                  .order(ordered_at: :desc).limit(lookback).includes(order_lines: :product)
    return [] if orders.empty?

    agg = Hash.new { |h, k| h[k] = { qty: 0.to_d, n: 0, uom: 'case', product: nil } }
    orders.each do |o|
      o.order_lines.each do |l|
        cell = agg[l.product_id]
        cell[:qty] += l.quantity
        cell[:n] += 1
        cell[:uom] = l.uom
        cell[:product] = l.product
      end
    end

    agg.map do |product_id, c|
      next unless c[:product]

      {
        product_id: product_id, sku: c[:product].sku, description: c[:product].description,
        suggested_qty: (c[:qty] / c[:n]).ceil, uom: c[:uom], seen_in: c[:n],
      }
    end.compact.sort_by { |r| -r[:seen_in] }
  end

  private

  def seller_stores
    ids = @seller.login_group_ids # login group across branches
    Store.where(seller_id: ids)
         .or(Store.where(route_id: Route.where(seller_id: ids).select(:id)))
         .where.not(vcsi_customer_ref: [nil, ''])
         .includes(:channel)
  end

  def sellout_scope(ids)
    SelloutSnapshot.where(store_id: ids, seller_id: nil, product_id: nil,
                          period_type: :mtd, period_date: @month)
  end

  # Bounding-box prefilter (cheap SQL) then exact same-channel peers.
  def nearby_peer_ids(store)
    dLat = PEER_RADIUS_KM / 111.0
    dLng = PEER_RADIUS_KM / (111.0 * Math.cos(store.latitude * Math::PI / 180).abs.clamp(0.01, 1))
    Store.where(channel_id: store.channel_id)
         .where.not(id: store.id)
         .where(latitude: (store.latitude - dLat)..(store.latitude + dLat))
         .where(longitude: (store.longitude - dLng)..(store.longitude + dLng))
         .limit(200)
         .pluck(:id)
  end

  # Nearest N stores of ANY channel by Haversine, bounding-box prefiltered.
  def nearest_store_ids(store, n)
    d_lat = NEARBY_RADIUS_KM / 111.0
    d_lng = NEARBY_RADIUS_KM / (111.0 * Math.cos(store.latitude * Math::PI / 180).abs.clamp(0.01, 1))
    Store.where.not(id: store.id)
         .where.not(status: :closed)
         .where(latitude: (store.latitude - d_lat)..(store.latitude + d_lat))
         .where(longitude: (store.longitude - d_lng)..(store.longitude + d_lng))
         .limit(400)
         .pluck(:id, :latitude, :longitude)
         .map { |id, lat, lng| [id, haversine(store.latitude, store.longitude, lat.to_f, lng.to_f)] }
         .sort_by { |_id, dist| dist }
         .first(n)
         .map(&:first)
  end

  # Distinct barcodes this store already carries in the window (confirmed vcsi
  # sellout or an SFA order) — the set to subtract from nearby whitespace.
  def store_carried_barcodes(store, since)
    set = Set.new
    store.store_sku_sellouts.in_window(since).where("pieces > 0").distinct.pluck(:it_barcode)
         .each { |bc| set << bc.to_s.strip if bc.present? }
    OrderLine.joins(:order, :product)
             .where(orders: { store_id: store.id }).where.not(orders: { status: :cancelled })
             .where("orders.ordered_at >= ?", since)
             .distinct.pluck("products.it_barcode")
             .each { |bc| set << bc.to_s.strip if bc.present? }
    set
  end

  def haversine(lat1, lon1, lat2, lon2)
    rkm = 6371.0
    d_lat = (lat2 - lat1) * Math::PI / 180
    d_lon = (lon2 - lon1) * Math::PI / 180
    a = Math.sin(d_lat / 2)**2 +
        Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) * Math.sin(d_lon / 2)**2
    2 * rkm * Math.asin([Math.sqrt(a), 1.0].min)
  end

  def month_elapsed_fraction
    days_in = @month.end_of_month.day
    elapsed = [Date.current.day, days_in].min
    (elapsed.to_f / days_in).clamp(0.03, 1.0)
  end

  def peso(n)
    "₱#{n.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
  end
end
