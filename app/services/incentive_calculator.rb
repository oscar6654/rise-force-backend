# Computes a seller's incentive earnings for a period across all live schemes.
# CONFIRMED earnings use vcsi_rise actuals (the true source, settles on sync);
# PROJECTED earnings use SFA presell/coverage so the seller sees a live number
# that reconciles down to confirmed — the same "encouragement" model as targets.
class IncentiveCalculator
  def initialize(seller, month: Date.current.beginning_of_month)
    @seller = seller
    @month = month
    @schemes = IncentiveScheme.live_on(@month).for_seller(seller).to_a
  end

  # => { confirmed_total:, projected_total:, schemes: [ {..per scheme..} ] }
  def call
    rows = @schemes.map { |s| compute(s) }.compact
    {
      confirmed_total: rows.sum { |r| r[:confirmed] }.round(2),
      projected_total: rows.sum { |r| r[:projected] }.round(2),
      schemes: rows,
    }
  end

  private

  def compute(scheme)
    case scheme.scheme_type
    when 'target_multiplier'      then target_multiplier(scheme)
    when 'focus_sku'              then focus_sku(scheme)
    when 'assortment_completion'  then assortment_completion(scheme)
    when 'coverage'               then coverage(scheme)
    end
  end

  def base(scheme, confirmed, projected, detail)
    { scheme_id: scheme.id, name: scheme.name, type: scheme.scheme_type,
      confirmed: confirmed.round(2), projected: projected.round(2), detail: detail }
  end

  # Tiered payout on attainment; confirmed uses vcsi actual, projected uses blended.
  def target_multiplier(scheme)
    target = @seller.target_for(@month).to_d
    return base(scheme, 0, 0, { note: 'no target' }) unless target.positive?

    confirmed_pct = (@seller.confirmed_actual(@month) / target * 100).round
    projected_pct = (@seller.blended_actual(@month) / target * 100).round
    base(scheme, payout_for(scheme, confirmed_pct), payout_for(scheme, projected_pct),
         { confirmed_pct: confirmed_pct, projected_pct: projected_pct })
  end

  def payout_for(scheme, attainment_pct)
    tiers = Array(scheme.cfg[:tiers]).sort_by { |t| t[:pct].to_i }
    earned = 0.to_d
    tiers.each do |t|
      earned = t[:payout].to_d * (t[:multiplier].presence || 1).to_d if attainment_pct >= t[:pct].to_i
    end
    earned + scheme.cfg[:base_payout].to_d
  end

  # ₱ per PIECE of focus SKUs. Focus SKUs are keyed by it_barcode — one barcode
  # can span several item_keys/SKUs and any of them counts. Confirmed = vcsi
  # per-barcode pieces; projected = presell.
  def focus_sku(scheme)
    barcodes = scheme_barcodes(scheme)
    rate = scheme.cfg[:rate_per_piece].to_d
    return base(scheme, 0, 0, { note: 'no focus SKUs' }) if barcodes.empty? || rate.zero?

    confirmed_pieces = SkuSelloutSnapshot.pieces_for_barcodes(@seller, barcodes, month: @month)
    projected_pieces = presell_pieces(barcodes)
    base(scheme, confirmed_pieces * rate, projected_pieces * rate,
         { confirmed_pieces: confirmed_pieces.to_i, projected_pieces: projected_pieces.to_i,
           barcodes: barcodes.size, rate_per_piece: rate.to_f })
  end

  # Focus barcodes from config. Prefer `it_barcodes`; fall back to a legacy
  # `product_ids` config by resolving those products' barcodes.
  def scheme_barcodes(scheme)
    codes = Array(scheme.cfg[:it_barcodes]).map { |b| b.to_s.strip }.reject(&:blank?)
    if codes.empty? && scheme.cfg[:product_ids].present?
      codes = Product.where(id: Array(scheme.cfg[:product_ids]).map(&:to_i))
                     .where.not(it_barcode: [nil, ""]).distinct.pluck(:it_barcode)
    end
    codes.uniq
  end

  # Pieces from SFA presell orders this month (case qty -> pcs via pcs_per_case),
  # matched on the product's it_barcode.
  def presell_pieces(barcodes)
    lines = OrderLine.joins(:order, :product)
                     .where(orders: { seller_id: @seller.id, status: %i[submitted batched downloaded invoiced] })
                     .where("orders.ordered_at >= ?", @month.beginning_of_day)
                     .where(products: { it_barcode: barcodes })
    lines.sum do |l|
      per_case = l.product.pcs_per_case.to_i
      l.uom == 'case_uom' ? l.quantity * (per_case.positive? ? per_case : 1) : l.quantity
    end.to_d
  end

  # ₱ per store that completes must-stock for an assortment type.
  def assortment_completion(scheme)
    type = scheme.cfg[:assortment_type].presence || 'focus'
    payout = scheme.cfg[:payout_per_store].to_d
    completed_confirmed = 0
    completed_projected = 0
    seller_stores.find_each do |store|
      c = store.assortment_compliance(type_code: type)
      next unless c && c[:must].positive?

      completed_projected += 1 if c[:carried] >= c[:must]
      completed_confirmed += 1 if c[:carried] >= c[:must] && store.active_in_vcsi?(@month)
    end
    base(scheme, completed_confirmed * payout, completed_projected * payout,
         { assortment_type: type, stores_completed: completed_projected, payout_per_store: payout.to_f })
  end

  def coverage(scheme)
    metric = scheme.cfg[:metric].presence || 'productive_call_pct'
    payout = scheme.cfg[:payout].to_d
    threshold = scheme.cfg[:threshold].to_i
    if metric == 'active_stores'
      count = seller_stores.active_in_vcsi(@month).count
      earned = count >= threshold ? payout + (count - threshold) * scheme.cfg[:per_unit].to_d : 0.to_d
      base(scheme, earned, earned, { metric: metric, active_stores: count, threshold: threshold })
    else
      pct = @seller.productive_call_pct(@month..Date.current) || 0
      earned = pct >= threshold ? payout : 0.to_d
      base(scheme, earned, earned, { metric: metric, productive_call_pct: pct, threshold: threshold })
    end
  end

  def seller_stores
    Store.where(seller: @seller).or(Store.where(route_id: Route.where(seller: @seller).select(:id)))
  end
end
