# Computes a live order preview: server-resolved prices, earned promo lines
# (shown as their own lines, never hidden in a total), order-level totals, and
# "threshold nudges" — the moment-of-sale prompt when the basket is close to
# unlocking a deal ("add 2 more → 1 free"). Used by POST /orders/preview so the
# app can pitch the deal before the seller submits.
class PromoEngine
  Line = Struct.new(:product_id, :sku, :description, :quantity, :uom, :unit_price,
                    :line_total, :line_type, :promo_id, :promo_name, keyword_init: true)

  def initialize(store, resolver: nil)
    @store = store
    @resolver = resolver || PricingResolver.new
    # Only promos the store can still avail — a per_store_limit'd deal ("2 TIMES
    # ONLY") drops out of the live preview once the cap is hit, matching what
    # order submission enforces, so the seller isn't shown a discount that will
    # be rejected.
    @promos = Promo.live_on(Date.current).eligible_for(store).includes(:promo_lines)
                   .select { |promo| promo.available_for?(store) }
  end

  # inputs: [{ product_id, quantity, uom }] (sale lines only; rewards are derived)
  #
  # Catalog prices are VAT-INCLUSIVE, but the store's exclusive discount and all
  # promos are EX-VAT. So the whole discount computation runs on ex-VAT amounts,
  # then VAT is added back on the net: a proper sales-invoice breakdown.
  def preview(inputs)
    vat = vat_rate
    incl = 1 + vat
    sale = build_sale_lines(inputs)                 # VAT-inclusive (catalog display)
    ex_sale = sale.map { |l| ex_line(l, incl) }     # ex-VAT copies, for the discount math
    by_product = ex_sale.group_by(&:product_id)

    earned = []
    nudges = []
    promo_total = 0.to_d # ex-VAT
    # Per-promo savings so the app can list WHICH promos applied and for how much.
    savings_by_promo = Hash.new { |h, k| h[k] = { promo_id: k, name: nil, kind: nil, savings: 0.to_d } }

    @promos.each do |promo|
      case promo.mechanic_type
      when 'buy_x_get_y', 'free_goods'
        e, n = apply_bxgy(promo, by_product)
        earned.concat(e)
        nudges.concat(n)
      when 'discount_percent', 'discount_amount'
        d = apply_discount(promo, by_product)
        promo_total += d
        record_saving(savings_by_promo, promo, d)
      when 'tiered_discount'
        d, n = apply_tiered(promo, ex_sale)
        promo_total += d
        nudges.concat(n)
        record_saving(savings_by_promo, promo, d)
      when 'bundle_price'
        d = apply_bundle(promo, by_product)
        promo_total += d
        record_saving(savings_by_promo, promo, d)
      when 'combo_percent'
        d, n = apply_combo(promo, by_product)
        promo_total += d
        nudges.concat(n)
        record_saving(savings_by_promo, promo, d)
      end
    end

    # Free-good savings = ex-VAT value of the free pieces, credited to their promo.
    free_goods_value = 0.to_d
    earned.each do |l|
      val = (l.quantity * (list_price(l.product_id) || 0)).to_d
      free_goods_value += val
      entry = savings_by_promo[l.promo_id]
      entry[:name] ||= l.promo_name
      entry[:kind] = 'free_goods'
      entry[:savings] += val
    end

    subtotal_incl = sale.sum(&:line_total)                # VAT-inclusive gross (Σ line totals)
    amount_ex     = (subtotal_incl / incl)                # basket ex of VAT
    promo_ex      = promo_total + free_goods_value
    store_rate    = @store.discount_rate.to_d
    store_disc    = (amount_ex * store_rate)              # store's exclusive discount (ex-VAT)
    vatable       = [amount_ex - promo_ex - store_disc, 0.to_d].max
    vat_amt       = vatable * vat
    total         = vatable + vat_amt

    promo_breakdown = savings_by_promo.values
                                      .select { |e| e[:savings].positive? }
                                      .map { |e| { promo_id: e[:promo_id], name: e[:name], kind: e[:kind], savings: e[:savings].round(2).to_f } }
    {
      lines: sale.map { |l| line_json(l) },
      earned_lines: earned.map { |l| line_json(l) },
      nudges: nudges,
      subtotal: subtotal_incl.round(2),        # VAT-inclusive gross
      amount_ex_vat: amount_ex.round(2),       # basket ex of VAT
      store_discount_rate: store_rate.to_f,
      store_discount: store_disc.round(2),     # ex-VAT
      promo_savings: promo_ex.round(2),        # ex-VAT
      promo_breakdown: promo_breakdown,        # ex-VAT, per promo
      vatable_sales: vatable.round(2),         # ex-VAT net after all discounts
      vat_rate: vat.to_f,
      vat: vat_amt.round(2),
      total: total.round(2),                   # VAT-inclusive amount due
    }
  end

  private

  # VAT rate the catalog prices already include (0.12 = 12%). Configurable so a
  # different jurisdiction/rate is a settings change, not a deploy.
  def vat_rate
    @vat_rate ||= SystemSetting.get("vat_rate", "0.12").to_d
  end

  # Strip VAT from a VAT-inclusive amount.
  def ex(amount)
    amount.to_d / (1 + vat_rate)
  end

  # An ex-VAT copy of a (VAT-inclusive) sale line, for the discount/promo math.
  def ex_line(line, incl)
    Line.new(product_id: line.product_id, sku: line.sku, description: line.description,
             quantity: line.quantity, uom: line.uom,
             unit_price: (line.unit_price / incl), line_total: (line.line_total / incl),
             line_type: line.line_type)
  end

  # Credit a discount-type promo's savings into the per-promo breakdown.
  def record_saving(acc, promo, amount)
    return unless amount.to_d.positive?

    entry = acc[promo.id]
    entry[:name] ||= promo.name
    entry[:kind] ||= promo.mechanic_type
    entry[:savings] += amount.to_d
  end

  def build_sale_lines(inputs)
    Array(inputs).filter_map do |raw|
      product = Product.find_by(id: raw[:product_id] || raw['product_id'])
      next unless product

      qty = (raw[:quantity] || raw['quantity']).to_d
      next if qty <= 0

      uom = (raw[:uom] || raw['uom'] || 'case').to_s
      unit = @resolver.price_for(@store.store_category, product, uom: uom) || @resolver.cost_for(product, uom) || 0
      Line.new(product_id: product.id, sku: product.sku, description: product.description,
               quantity: qty, uom: uom, unit_price: unit.to_d.round(2),
               line_total: (unit.to_d * qty).round(2), line_type: 'sale')
    end
  end

  # Buy X of a qualifying product, get Y of a reward product free.
  def apply_bxgy(promo, by_product)
    qualifying = promo.promo_lines.select(&:role_qualifying?)
    rewards = promo.promo_lines.select(&:role_reward?)
    return [[], []] if qualifying.empty? || rewards.empty?

    earned = []
    nudges = []
    qualifying.each do |q|
      q_prod = line_rep_product(q)
      # min_qty is in PIECES. Count across the whole barcode group (any pack the
      # store ordered counts) so a case (pcs_per_case) or loose pieces both add up.
      have = line_product_ids(q).sum { |pid| pieces_of(by_product[pid], Product.find_by(id: pid)) }
      min = q.min_qty.to_i
      next if min <= 0

      if have >= min
        multiples = (have / min).floor
        rewards.each do |r|
          reward_product = line_rep_product(r)
          next unless reward_product

          free_qty = multiples * r.reward_qty.to_i
          next if free_qty <= 0

          earned << Line.new(product_id: reward_product.id, sku: reward_product.sku,
                             description: reward_product.description, quantity: free_qty.to_d,
                             uom: 'case', unit_price: 0, line_total: 0,
                             line_type: 'promo_free_good', promo_id: promo.id, promo_name: promo.name)
        end
      elsif have.positive? && (min - have) <= [min * 0.34, 3].max
        # Close to the threshold — nudge the seller to upsell (in pieces).
        need = (min - have).to_i
        reward_names = rewards.map { |r| line_rep_product(r)&.description }.compact.join(', ')
        nudges << {
          promo_id: promo.id, promo: promo.name,
          text: "Add #{need} more pc of #{q_prod&.description || 'unit'} → free #{reward_names}",
          need_qty: need, product_id: q_prod&.id,
        }
      end
    end
    [earned, nudges]
  end

  def apply_discount(promo, by_product)
    total = 0.to_d
    promo.promo_lines.select(&:role_qualifying?).each do |q|
      line_product_ids(q).each do |pid|
        (by_product[pid] || []).each do |l|
          if promo.discount_percent? && q.discount_rate
            total += (l.line_total * q.discount_rate.to_d).round(2)
          elsif promo.discount_amount? && q.discount_amount
            total += (q.discount_amount.to_d * l.quantity).round(2)
          end
        end
      end
    end
    total
  end

  # Combo: buy SPECIFIC items, each at its own minimum pieces → X% off those
  # items (ex-VAT). Applies only when EVERY qualifying item meets its minimum.
  # Returns [discount, nudges]; nudges the shortfall once the seller has started.
  def apply_combo(promo, by_product)
    qualifying = promo.promo_lines.select(&:role_qualifying?)
    rate = promo.combo_rate
    return [0.to_d, []] if qualifying.empty? || !rate.positive?

    shortfalls = []
    qualifying.each do |q|
      min = q.min_qty.to_i
      next if min <= 0

      have = line_product_ids(q).sum { |pid| pieces_of(by_product[pid], Product.find_by(id: pid)) }
      shortfalls << { need: min - have, product: line_rep_product(q) } if have < min
    end

    if shortfalls.any?
      # Only nudge once they've added at least one of the combo's items.
      started = qualifying.any? { |q| line_product_ids(q).any? { |pid| (by_product[pid] || []).any? } }
      return [0.to_d, []] unless started

      parts = shortfalls.map { |s| "#{s[:need]} pc #{s[:product]&.description}" }.join(', ')
      return [0.to_d, [{ promo_id: promo.id, promo: promo.name,
                         text: "Add #{parts} → #{(rate * 100).to_i}% off the set" }]]
    end

    # X% off the ex-VAT total of the qualifying items actually in the cart.
    base = qualifying.flat_map { |q| line_product_ids(q) }.uniq.sum do |pid|
      (by_product[pid] || []).sum(&:line_total)
    end
    [(base * rate).round(2), []]
  end

  # Bundle price: buy min_qty PIECES of the qualifying SKU for a fixed price
  # (e.g. "any 3 for ₱100"). Discount = (normal price of the bundle − fixed) × bundles.
  def apply_bundle(promo, by_product)
    total = 0.to_d
    promo.promo_lines.select(&:role_qualifying?).each do |q|
      prod = line_rep_product(q)
      min = q.min_qty.to_i
      next unless prod && min.positive? && q.fixed_price

      have = line_product_ids(q).sum { |pid| pieces_of(by_product[pid], Product.find_by(id: pid)) }
      bundles = (have / min).floor
      next if bundles <= 0

      # ex-VAT unit price vs the (ex-VAT) fixed bundle price.
      unit_pc = ex(@resolver.price_for(@store.store_category, prod, uom: :pc) || @resolver.cost_for(prod, 'pc') || 0)
      saving = (unit_pc * min) - q.fixed_price.to_d
      total += (saving * bundles).round(2) if saving.positive?
    end
    total
  end

  # Tiered volume deal. basis "pieces": pick the highest piece tier the qualifying
  # SKUs reach and take that % off their subtotal. basis "amount": pick the highest
  # spend tier and take that fixed ₱ off, once. A near-miss becomes an upsell nudge.
  def apply_tiered(promo, sale)
    tiers = promo.tiers
    return [0.to_d, []] if tiers.empty?

    qualifying = qualifying_product_ids(promo)
    lines = qualifying.empty? ? sale : sale.select { |l| qualifying.include?(l.product_id) }
    return [0.to_d, []] if lines.empty?

    if promo.tier_basis == "amount"
      apply_amount_tiers(promo, tiers, lines)
    else
      apply_piece_tiers(promo, tiers, lines)
    end
  end

  def apply_piece_tiers(promo, tiers, lines)
    product = Product.find_by(id: lines.first&.product_id)
    have = lines.sum { |l| pieces_of([l], Product.find_by(id: l.product_id)) }
    subtotal = lines.sum(&:line_total)
    tier = tiers.reverse.find { |t| have >= t["min"].to_f }
    nxt  = tiers.find { |t| t["min"].to_f > have }
    need = nxt ? (nxt["min"].to_f - have).to_i : 0
    of = product ? " #{product.description}" : ""
    nudges = tier_nudge(promo, nxt, need, "#{need} pc#{of}", product_id: product&.id) if nxt
    return [(subtotal * tier["rate"].to_d).round(2), [nudges].compact] if tier

    [0.to_d, [nudges].compact]
  end

  def apply_amount_tiers(promo, tiers, lines)
    spent = lines.sum(&:line_total)
    tier = tiers.reverse.find { |t| spent >= t["min"].to_f }
    nxt  = tiers.find { |t| t["min"].to_f > spent }
    need = nxt ? (nxt["min"].to_f - spent).round : 0
    nudges = tier_nudge(promo, nxt, need, "₱#{peso(need)} more") if nxt
    return [tier["amount"].to_d.round(2), [nudges].compact] if tier

    [0.to_d, [nudges].compact]
  end

  def tier_nudge(promo, tier, need, need_text, product_id: nil)
    label = tier["rate"] ? "#{(tier['rate'].to_f * 100).round}% off" : "₱#{peso(tier['amount'])} off"
    { promo_id: promo.id, promo: promo.name, text: "Add #{need_text} → #{label}", need_qty: need, product_id: product_id }
  end

  # Whole-peso amount with thousands separators (2000.0 -> "2,000").
  def peso(amount)
    amount.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  def qualifying_product_ids(promo)
    promo.promo_lines.select(&:role_qualifying?).flat_map { |q| line_product_ids(q) }.uniq
  end

  # All product ids a promo line targets. Promos are BARCODE-based, and the
  # catalog collapses each barcode to one representative SKU — so a line with an
  # it_barcode must match the WHOLE barcode group (which contains the
  # representative the seller actually orders), not the single product_id the
  # importer happened to stamp on the line. Falls back to product_id only when
  # there is no barcode. Memoized per barcode.
  def line_product_ids(line)
    if line.it_barcode.present?
      (@bc_ids ||= {})[line.it_barcode] ||= Product.where(it_barcode: line.it_barcode).pluck(:id)
    elsif line.product_id
      [line.product_id]
    else
      []
    end
  end

  # The catalog-visible SKU for a promo line's barcode group (highest case_cost
  # active — same rule as Product.barcode_representative_ids), so a free good or
  # bundle resolves to an orderable representative, not a hidden sibling.
  def line_rep_product(line)
    if line.it_barcode.present?
      (@bc_rep ||= {})[line.it_barcode] ||=
        Product.active.where(it_barcode: line.it_barcode)
               .order(Arel.sql("case_cost DESC NULLS LAST, item_cost DESC NULLS LAST, sku ASC")).first
    else
      Product.find_by(id: line.product_id)
    end
  end

  # Total ordered PIECES for a product across its case + pc lines.
  # A case counts as pcs_per_case pieces (default 1 if unknown).
  def pieces_of(lines, product)
    per = product&.pcs_per_case.to_i
    per = 1 if per <= 0
    Array(lines).sum { |l| l.uom.to_s == 'pc' ? l.quantity : l.quantity * per }
  end

  # ex-VAT case price, used to value free goods in the savings breakdown.
  def list_price(product_id)
    p = Product.find_by(id: product_id)
    return nil unless p

    ex(@resolver.price_for(@store.store_category, p, uom: 'case') || @resolver.cost_for(p, 'case') || 0)
  end

  def line_json(l)
    {
      product_id: l.product_id, sku: l.sku, description: l.description,
      quantity: l.quantity.to_f, uom: l.uom, unit_price: l.unit_price.to_f,
      line_total: l.line_total.to_f, line_type: l.line_type,
      promo_id: l.promo_id, promo_name: l.promo_name,
    }
  end
end
