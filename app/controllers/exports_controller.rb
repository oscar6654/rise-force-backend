require "csv"

# Download the current master data as CSV — the counterpart to the bulk CSV
# imports, so an operator can export → edit → re-upload. Column formats mirror
# each importer's expected headers so the big masters round-trip (stores,
# products, channel availability, promos). The console-managed lookups
# (channels, categories, tiers, store categories) and the pricing matrix /
# assortment items export a clean, readable snapshot for review and backup.
class ExportsController < ApplicationController
  # kind => RBAC resource authorized for :view
  KINDS = {
    "products"           => :product,
    "stores"             => :store,
    "product_channels"   => :product,
    "promos"             => :promo,
    "channels"           => :channel,
    "product_categories" => :product_category,
    "product_tiers"      => :product_tier,
    "store_categories"   => :store_category,
    "assortments"        => :assortment,
    "pricing"            => :pricing,
  }.freeze

  # GET /exports/:kind  → streams "<kind>_<date>.csv"
  def show
    kind = params[:kind].to_s
    resource = KINDS[kind]
    raise ActionController::RoutingError, "Unknown export '#{kind}'" if resource.nil?

    authorize!(resource, :view)
    send_data send("export_#{kind}"), filename: "#{kind}_#{Date.current.iso8601}.csv", type: "text/csv"
  end

  private

  # ---- heavy masters: columns mirror the importer so they round-trip ----------

  PRODUCT_COLS = %w[itemkey desc1 desc2 brand_code brand_name category_code category_name item_tier abc_class
                    stock_uom purchase_uom selling_uom items_per_case it_barcode cs_barcode sw_barcode
                    item_cost case_cost tax status].freeze

  def export_products
    csv_for(PRODUCT_COLS) do |csv|
      Product.includes(:brand, :product_category, :product_tier).find_each do |p|
        csv << [p.sku, p.description, p.desc2, p.brand&.code, p.brand&.name,
                p.product_category&.code, p.product_category&.name, p.product_tier&.code, p.abc_class,
                p.stock_uom, p.purchase_uom, p.selling_uom, p.pcs_per_case, p.it_barcode, p.cs_barcode, p.sw_barcode,
                p.item_cost, p.case_cost, p.tax_code, p.status]
      end
    end
  end

  STORE_COLS = %w[store_code name owner_name address contact_number latitude longitude branch_code channel_code
                  category status discount seller_code route_code route_name vcsi_customer_ref segment chain
                  sub_chain distribution_type tin visit_frequency week_pattern visit_day visit_sequence].freeze

  def export_stores
    csv_for(STORE_COLS) do |csv|
      Store.includes(:branch, :channel, :store_category, :seller, :route).find_each do |s|
        d = s.discount_rate.to_d
        csv << [s.store_code, s.name, s.owner_name, s.address, s.contact_number, s.latitude, s.longitude,
                s.branch&.code, s.channel&.code, s.store_category&.code, s.status,
                (d.positive? ? num(d * 100) : nil), s.seller&.seller_code, s.route&.code, s.route&.name,
                s.vcsi_customer_ref, s.segment, s.chain, s.sub_chain, s.distribution_type, s.tin,
                s.visit_frequency, s.week_pattern, s.visit_day, s.visit_sequence]
      end
    end
  end

  def export_product_channels
    csv_for(%w[item_key channel_code available]) do |csv|
      ProductChannel.includes(:product, :channel).find_each do |pc|
        csv << [pc.product&.sku, pc.channel&.code, true]
      end
    end
  end

  def export_promos
    csv_for(ImportsController::PROMO_HEADERS) do |csv|
      Promo.includes(:promo_lines, promo_eligibilities: %i[channel store_category_ref branch]).find_each do |p|
        csv << promo_row(p)
      end
    end
  end

  # ---- console-managed lookups: a clean snapshot (code is the stable key) ------

  def export_channels
    csv_for(%w[code name description status]) do |csv|
      Channel.order(:code).each { |c| csv << [c.code, c.name, c.description, c.status] }
    end
  end

  def export_product_categories
    csv_for(%w[code name status]) do |csv|
      ProductCategory.order(:code).each { |c| csv << [c.code, c.name, c.status] }
    end
  end

  def export_product_tiers
    csv_for(%w[code name sort_order active]) do |csv|
      ProductTier.order(:sort_order, :code).each { |t| csv << [t.code, t.name, t.sort_order, t.active] }
    end
  end

  def export_store_categories
    csv_for(%w[code name letter sort_order active]) do |csv|
      StoreCategory.order(:sort_order, :code).each { |c| csv << [c.code, c.name, c.letter, c.sort_order, c.active] }
    end
  end

  # ---- assortments: one row per item (assortment metadata + its SKU) -----------

  def export_assortments
    cols = %w[assortment_name branch_code channel_code store_category assortment_type effective_from effective_to
              reset_months it_barcode sku description must_stock priority]
    csv_for(cols) do |csv|
      AssortmentItem.includes(:product, assortment: %i[branch channel store_category_ref assortment_type]).find_each do |ai|
        a = ai.assortment
        csv << [a.name, a.branch&.code, a.channel&.code, a.store_category_ref&.code, a.assortment_type&.code,
                a.effective_from, a.effective_to, a.reset_months,
                ai.product&.it_barcode, ai.product&.sku, ai.product&.description, ai.must_stock, ai.priority]
      end
    end
  end

  # ---- pricing: one row per matrix cell (version × category × tier) ------------

  def export_pricing
    cols = %w[version_number version_name status effective_date store_category_code product_tier_code markup_percent]
    csv_for(cols) do |csv|
      PricingRule.includes(:pricing_version, :store_category, :product_tier)
                 .joins(:pricing_version).order("pricing_versions.version_number").find_each do |r|
        v = r.pricing_version
        csv << [v&.version_number, v&.name, v&.status, v&.effective_date,
                r.store_category&.code, r.product_tier&.code, num(r.markup_rate.to_d * 100)]
      end
    end
  end

  # ---- helpers ----------------------------------------------------------------

  def csv_for(cols)
    CSV.generate do |csv|
      csv << cols
      yield csv
    end
  end

  # Reconstruct one promo's CSV row (matches ImportsController::PROMO_HEADERS), so
  # a downloaded promo re-imports through PromosImporter.
  def promo_row(p)
    q      = p.promo_lines.find(&:role_qualifying?)
    reward = p.promo_lines.find { |l| l.role == "reward" }
    elig   = p.promo_eligibilities.first
    cfg    = p.config || {}
    h = {
      "code" => p.code, "name" => p.name, "mechanic" => p.mechanic_type, "basis" => cfg["basis"],
      "status" => p.status, "start_date" => p.start_date, "end_date" => p.end_date,
      "per_store_limit" => p.per_store_limit,
      "channel_code" => p.promo_eligibilities.filter_map { |e| e.channel&.code }.uniq.join(";").presence,
      "category" => elig&.store_category_ref&.code, "branch_code" => elig&.branch&.code,
    }
    case p.mechanic_type
    when "tiered_discount"
      h["tiers"] = p.tiers.map { |t| "#{num(t['min'])}:#{t['rate'] || t['amount']}" }.join("|")
    when "multivariant_percent"
      h["tiers"] = p.multivariant_tiers.map { |t| "#{t['min_skus']}:#{t['rate']}" }.join("|")
      h["items"] = qualifying_items(p)
    when "combo_percent"
      h["items"] = qualifying_items(p)
      h["discount_rate"] = cfg["rate"]
    when "buy_x_get_y", "free_goods"
      h.merge!("it_barcode" => q&.it_barcode, "min_qty" => q&.min_qty,
               "reward_qty" => reward&.reward_qty, "reward_barcode" => reward&.it_barcode)
    when "bundle_price"
      h.merge!("it_barcode" => q&.it_barcode, "min_qty" => q&.min_qty, "fixed_price" => q&.fixed_price)
    when "discount_percent"
      h.merge!("it_barcode" => q&.it_barcode, "discount_rate" => q&.discount_rate)
    when "discount_amount"
      h.merge!("it_barcode" => q&.it_barcode, "discount_amount" => q&.discount_amount)
    end
    ImportsController::PROMO_HEADERS.map { |col| h[col] }
  end

  def qualifying_items(promo)
    promo.promo_lines.select(&:role_qualifying?).map { |l| "#{l.it_barcode}:#{l.min_qty.to_i}" }.join("|")
  end

  # Integer when whole (2.5 → "2.5", 15.0 → "15") so the sheet reads cleanly.
  def num(decimal)
    n = decimal.to_d
    (n == n.to_i ? n.to_i : n.to_f).to_s
  end
end
