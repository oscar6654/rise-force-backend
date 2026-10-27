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
    "sellers"            => :seller,
    "product_channels"   => :product,
    "promos"             => :promo,
    "channels"           => :channel,
    "product_categories" => :product_category,
    "product_tiers"      => :product_tier,
    "store_categories"   => :store_category,
    "assortments"        => :assortment,
    "pricing"            => :pricing,
    "warehouses"         => :warehouse,
    "storage_locations"  => :storage_location,
    "inventory"          => :inventory,
    "stock_movements"    => :stock_movement,
  }.freeze

  # GET /exports/:kind  → streams "<kind>_<date>.csv"
  def show
    kind = params[:kind].to_s
    resource = KINDS[kind]
    raise ActionController::RoutingError, "Unknown export '#{kind}'" if resource.nil?

    authorize!(resource, :view)
    send_data send("export_#{kind}"), filename: export_filename(kind), type: "text/csv"
  end

  # Includes the warehouse code and/or the date window in the filename when the
  # download is scoped, so per-warehouse / dated exports are distinguishable.
  def export_filename(kind)
    whs = Warehouse.where(id: params[:warehouse_id]).pick(:whs_code) if params[:warehouse_id].present?
    from = params[:from].presence
    to   = params[:to].presence
    parts = [kind, whs]
    parts << (from || to ? "#{from || 'start'}_to_#{to || 'now'}" : Date.current.iso8601)
    "#{parts.compact.join('_')}.csv"
  end

  private

  # ---- heavy masters: columns mirror the importer so they round-trip ----------

  PRODUCT_COLS = %w[itemkey desc1 desc2 brand_code brand_name category_code category_name item_tier abc_class
                    stock_uom purchase_uom selling_uom items_per_case items_per_shrinkwrap shrinkwraps_per_case
                    casesperpallet layersperpallet casestatfactor caseheight caseweight casevolume
                    it_barcode cs_barcode sw_barcode item_cost case_cost tax status].freeze

  def export_products
    csv_for(PRODUCT_COLS) do |csv|
      Product.includes(:brand, :product_category, :product_tier).find_each do |p|
        csv << [p.sku, p.description, p.desc2, p.brand&.code, p.brand&.name,
                p.product_category&.code, p.product_category&.name, p.product_tier&.code, p.abc_class,
                p.stock_uom, p.purchase_uom, p.selling_uom, p.pcs_per_case, p.items_per_shrinkwrap, p.shrinkwraps_per_case,
                p.casesperpallet, p.layersperpallet, p.casestatfactor, p.caseheight, p.caseweight, p.casevolume,
                p.it_barcode, p.cs_barcode, p.sw_barcode, p.item_cost, p.case_cost, p.tax_code, p.status]
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

  # Columns mirror SellersImporter so sellers round-trip. PINs are never exported
  # (only the digests exist); a blank pin/diser_pin on re-import keeps the current one.
  SELLER_COLS = %w[seller_code name branch_code status section vcsi_sales_rep_ref supervisor_name gsm_name
                   om_name sales_target diser_code diser_name primary_seller_code manager_codes
                   warehouse_code wms_enabled pin diser_pin].freeze

  def export_sellers
    csv_for(SELLER_COLS) do |csv|
      Seller.includes(:branch, :primary_seller, :managers, :warehouse).find_each do |s|
        csv << [s.seller_code, s.name, s.branch&.code, s.status, s.section, s.vcsi_sales_rep_ref,
                s.supervisor_name, s.gsm_name, s.om_name, s.sales_target,
                s.diser_code, s.diser_name, s.primary_seller&.seller_code,
                s.managers.map(&:code).join(";").presence, s.warehouse&.whs_code, s.wms_enabled, nil, nil]
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

  # ---- WMS exports (round-trip with the WMS importers) ------------------------

  def export_warehouses
    csv_for(%w[whs_code wh_name branch_code address status wms_enabled allocation_strategy]) do |csv|
      Warehouse.includes(:branch).order(:whs_code).each do |w|
        csv << [w.whs_code, w.wh_name, w.branch&.code, w.address, w.status, w.wms_enabled, w.allocation_strategy]
      end
    end
  end

  STORAGE_LOCATION_COLS = %w[warehouse_code loc_code name zone aisle bay level loc_type pickable
                             allow_mixed_lots slot_capacity pick_sequence allowed_abc_classes
                             allowed_brand_codes status].freeze

  def export_storage_locations
    brand_codes = Brand.pluck(:id, :code).to_h
    csv_for(STORAGE_LOCATION_COLS) do |csv|
      StorageLocation.includes(:warehouse).order(:warehouse_id, :pick_sequence, :loc_code).find_each do |l|
        csv << [l.warehouse.whs_code, l.loc_code, l.name, l.zone, l.aisle, l.bay, l.level, l.loc_type,
                l.pickable, l.allow_mixed_lots, l.slot_capacity, l.pick_sequence,
                Array(l.allowed_abc_classes).join(";"),
                Array(l.allowed_brand_ids).filter_map { |id| brand_codes[id] }.join(";"), l.status]
      end
    end
  end

  def export_inventory
    cols = %w[warehouse_code loc_code itemkey it_barcode lot_code received_date expiry_date
              qty_on_hand qty_allocated qty_locked qty_available status]
    scope = InventoryLot.includes(:warehouse, :storage_location, :product)
    scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
    csv_for(cols) do |csv|
      scope.find_each do |lot|
        csv << [lot.warehouse.whs_code, lot.storage_location&.loc_code, lot.product&.sku, lot.product&.it_barcode,
                lot.lot_code, lot.received_date, lot.expiry_date, lot.qty_on_hand, lot.qty_allocated,
                lot.qty_locked, lot.qty_available, lot.status]
      end
    end
  end

  # Audit trail: every counter change, who did it (warehouse staff on the floor,
  # or the console user for office actions like adjust/reconcile), and the lot /
  # order / receipt it touched. Honours the same filters as the ledger view
  # (warehouse, type, staff, from/to date window) so a date-scoped download
  # matches what is on screen. find_each batches by id — ascending id is
  # chronological for an append-only ledger, so the CSV reads oldest → newest.
  def export_stock_movements
    cols = %w[occurred_at warehouse_code movement_type field quantity itemkey lot_code loc_code to_loc_code
              fulfillment_ref receipt_ref reason staff_code user_email]
    csv_for(cols) do |csv|
      StockMovement.filtered(params)
                   .includes(:warehouse, :product, :inventory_lot, :storage_location, :to_storage_location,
                             :fulfillment_order, :receipt, :warehouse_staff, :user).find_each do |m|
        csv << [m.occurred_at&.iso8601, m.warehouse.whs_code, m.movement_type, m.field, m.quantity,
                m.product&.sku, m.inventory_lot&.lot_code, m.storage_location&.loc_code,
                m.to_storage_location&.loc_code, m.fulfillment_order&.reference_no, m.receipt&.po_ref,
                m.reason, m.warehouse_staff&.staff_code, m.user&.email]
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
