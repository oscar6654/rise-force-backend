class ImportsController < ApplicationController
  # kind => [resource for authorization, importer class]
  KINDS = {
    "products"          => [:product,          "Import::ProductsImporter",         "/products"],
    "stores"            => [:store,            "Import::StoresImporter",           "/stores"],
    "sellers"           => [:seller,           "Import::SellersImporter",          "/sellers"],
    "product_channels"  => [:product,          "Import::ProductChannelsImporter",  "/product_channels"],
    "promos"            => [:promo,            "Import::PromosImporter",           "/promos"],
    # WMS masters + feeds
    "warehouses"        => [:warehouse,        "Import::WarehousesImporter",       "/warehouses"],
    "storage_locations" => [:storage_location, "Import::StorageLocationsImporter", "/wms/storage_locations"],
    "inventory"         => [:inventory,        "Import::InventoryImporter",        "/wms/inventory"],
    "asn"               => [:receipt,          "Import::AsnImporter",              "/wms/receipts"],
    "dispatch_orders"   => [:fulfillment_order, "Import::DispatchOrdersImporter",  "/wms/demand"],
    "returns"           => [:wms_return,       "Import::ReturnsImporter",          "/wms/returns"]
  }.freeze

  # Importers that take a default branch for NEW rows lacking a branch_code.
  DEFAULT_BRANCH_KINDS = %w[stores sellers].freeze

  before_action :set_kind

  def new
    authorize!(@resource, :create)
  end

  # Downloadable example CSV, pre-filled with real codes/barcodes from this
  # deployment so it imports as-is — the operator edits the values from there.
  def sample
    authorize!(@resource, :view)
    send_data sample_csv(@kind), filename: "#{@kind}_example.csv", type: "text/csv"
  end

  # Files at/under this row count import inline (instant redirect with counts);
  # bigger files are handed to a background job so the request never times out.
  INLINE_ROW_LIMIT = 2_000

  def create
    authorize!(@resource, :create)
    file = params[:file]
    return redirect_to(new_import_path(@kind), alert: "Choose a CSV file first.") if file.blank?

    data = file.read
    row_count = [data.count("\n") - 1, 0].max # minus the header; good enough to pick a lane

    if row_count > INLINE_ROW_LIMIT
      enqueue_background_import(data, file, row_count)
    else
      run_inline_import(data, file)
    end
  rescue StandardError => e
    redirect_to new_import_path(@kind), alert: "Import failed: #{e.message}"
  end

  private

  def set_kind
    @kind = params[:kind].to_s
    config = KINDS[@kind]
    raise ActionController::RoutingError, "Unknown import" if config.nil?

    @resource, @importer_class, @back_path = config
  end

  # Small file: import in the request and report counts immediately.
  def run_inline_import(data, file)
    importer = @importer_class.constantize
    log = if DEFAULT_BRANCH_KINDS.include?(@kind)
            importer.new(data, user: current_user, filename: file.original_filename,
                         default_branch: current_user.branch || Branch.first).call
          else
            importer.new(data, user: current_user, filename: file.original_filename,
                         mode: params[:mode]).call
          end
    notice = "Imported #{log.processed_rows}/#{log.total_rows} rows" \
             "#{log.error_count.positive? ? " (#{log.error_count} rejected — see Logs)" : ""}."
    redirect_to @back_path, notice: notice
  end

  # Large file: create the JobLog now, stash the CSV on it, and process in the
  # background. The operator watches it go running → completed on the Logs page.
  def enqueue_background_import(data, file, row_count)
    klass = @importer_class.constantize
    log = JobLog.create!(job_type: klass::JOB_TYPE, triggered_by: current_user,
                         filename: file.original_filename)
    log.source_file.attach(io: StringIO.new(data), filename: file.original_filename,
                           content_type: "text/csv")
    Import::RunJob.perform_later(log.id, @importer_class, @kind, params[:mode].presence)
    redirect_to job_logs_path,
                notice: "#{file.original_filename} (~#{row_count} rows) queued — importing in the " \
                        "background. Refresh this page to watch progress."
  end

  require "csv"
  # Real values so the sample imports without edits; fall back to placeholders.
  def sample_csv(kind)
    case kind
    when "promos"          then promos_sample
    when "product_channels" then product_channels_sample
    when "products"        then products_sample
    when "stores"          then stores_sample
    when "sellers"         then sellers_sample
    when "warehouses"        then warehouses_sample
    when "storage_locations" then storage_locations_sample
    when "inventory"         then inventory_sample
    when "asn"               then asn_sample
    when "dispatch_orders"   then dispatch_orders_sample
    when "returns"           then returns_sample
    else "\n"
    end
  end

  def returns_sample
    wh = Warehouse.order(:whs_code).first&.whs_code || "WH-MAIN"
    store = Store.order(:store_code).first&.store_code || "ST-0001"
    p = Product.where.not(it_barcode: [nil, ""]).order(:id).first
    sku = p&.sku || "KOP-3IN1-10S"; bc = p&.it_barcode || "4800016641"
    CSV.generate do |csv|
      csv << %w[warehouse_code ref store_code itemkey it_barcode qty uom notes]
      csv << [wh, "RET-2026-001", store, sku, bc, "3", "case",
              "Keyed on itemkey (same as the ASN). Leave disposition OUT — the operator tags each line " \
              "saleable/damaged/quarantine when processing and the system suggests where to drop it. uom = case or pc."]
      csv << [wh, "RET-2026-001", store, sku, bc, "8", "pc", "Loose returns: add a pc line."]
    end
  end

  PROMO_HEADERS = %w[code name mechanic basis it_barcode tiers items min_qty reward_qty reward_barcode
                     discount_rate discount_amount fixed_price channel_code category branch_code
                     start_date end_date per_store_limit status notes].freeze

  SELLER_HEADERS = %w[seller_code name branch_code status section vcsi_sales_rep_ref supervisor_name gsm_name
                      om_name sales_target diser_code diser_name primary_seller_code manager_codes
                      warehouse_code wms_enabled pin diser_pin notes].freeze

  # One worked example of EVERY mechanic, each with a plain-English `notes`
  # column (the importer ignores unknown columns like `notes`).
  def promos_sample
    bc = Product.where.not(it_barcode: [nil, ""]).order(:id).limit(3).pluck(:it_barcode)
    b1 = bc[0] || "4800016641"
    b2 = bc[1] || b1
    b3 = bc[2] || b2
    chan_codes = Channel.order(:code).limit(2).pluck(:code)
    chan = chan_codes[0]
    multi_chan = chan_codes.join(";") # two channels in one cell = promo covers both
    sd = Date.current.beginning_of_month
    ed = Date.current.end_of_month
    rows = [
      { code: "PCT-5", name: "5% off SKU", mechanic: "discount_percent", it_barcode: b1, discount_rate: "0.05",
        start_date: sd, end_date: ed, status: "active", notes: "Flat 5% off this SKU, any quantity." },
      { code: "AMT-2", name: "PHP2 off per pc", mechanic: "discount_amount", it_barcode: b1, discount_amount: "2",
        start_date: sd, end_date: ed, status: "active", notes: "PHP 2 off each piece sold." },
      { code: "BXGY-60-1", name: "Buy 60 get 1", mechanic: "buy_x_get_y", it_barcode: b1, min_qty: "60", reward_qty: "1",
        per_store_limit: "2", start_date: sd, end_date: ed, status: "active",
        notes: "Buy 60 pcs (5 cases) -> 1 free. Reward is the same SKU unless you set reward_barcode." },
      { code: "FG-24-2", name: "Buy 24 get 2 free", mechanic: "free_goods", it_barcode: b1, min_qty: "24", reward_qty: "2",
        start_date: sd, end_date: ed, status: "active", notes: "Buy 24 pcs -> 2 free goods (same as buy-x-get-y)." },
      { code: "BUNDLE-3-100", name: "3 for PHP100", mechanic: "bundle_price", it_barcode: b1, min_qty: "3", fixed_price: "100",
        start_date: sd, end_date: ed, status: "active", notes: "Any 3 pcs of this SKU for a fixed PHP 100." },
      { code: "VOL-4-7", name: "Volume 4/7%", mechanic: "tiered_discount", basis: "pieces", it_barcode: b1, tiers: "18:0.04|72:0.07",
        channel_code: chan, start_date: sd, end_date: ed, status: "active",
        notes: "4% off 18-71 pcs, 7% off 72+. tiers = min:rate|min:rate (0.04 = 4%)." },
      { code: "VOL-144", name: "4% at 144 pcs", mechanic: "tiered_discount", basis: "pieces", it_barcode: b2, tiers: "144:0.04",
        start_date: sd, end_date: ed, status: "active", notes: "Single threshold: 4% off at 144 pcs or more." },
      { code: "COMBO-10", name: "Buy set get 10%", mechanic: "combo_percent", items: "#{b1}:24|#{b2}:12", discount_rate: "0.10",
        channel_code: chan, start_date: sd, end_date: ed, status: "active",
        notes: "Buy #{b1} >=24pc AND #{b2} >=12pc -> 10% off those items (ex-VAT). items = barcode:minpc|barcode:minpc, discount_rate = 0.10." },
      { code: "MVP-2-3", name: "Mix any 2->8% / all 3->12%", mechanic: "multivariant_percent",
        items: "#{b1}:2|#{b2}:2|#{b3}:2", tiers: "2:0.08|3:0.12",
        channel_code: chan, start_date: sd, end_date: ed, status: "active",
        notes: "Multivariant mix & match: buy ANY 2 of the listed SKUs (each >= its MOQ pieces) -> 8%; all 3 -> 12% off those items (ex-VAT). items = barcode:MOQpc|... , tiers = minSKUs:rate (2:0.08 = any 2 variants -> 8%). MOQ differs per brand (e.g. 2pc vs 6pc)." },
      { code: "SPEND-100-300", name: "Spend and save", mechanic: "tiered_discount", basis: "amount", tiers: "1200:100|3000:300",
        start_date: sd, end_date: ed, status: "active",
        notes: "PHP 100 off >= PHP 1200, PHP 300 off >= PHP 3000. Whole order (no it_barcode). tiers = min:amount." },
      { code: "HFSWS-SPEND", name: "HFS WS 50/75/100k", mechanic: "tiered_discount", basis: "amount",
        tiers: "50000:2000|75000:3000|100000:4000", channel_code: multi_chan, per_store_limit: "2",
        start_date: sd, end_date: ed, status: "active",
        notes: "Spend 50k->2k / 75k->3k / 100k->4k off, whole order, 2x per store. channel_code lists TWO channels joined by ';' so one promo covers both." },
    ]
    CSV.generate do |csv|
      csv << PROMO_HEADERS
      rows.each { |r| csv << PROMO_HEADERS.map { |h| r[h.to_sym] } }
    end
  end

  def sellers_sample
    branch = Branch.order(:code).first&.code || "HQ"
    mgr = Manager.order(:code).first&.code
    wh = Warehouse.wms.order(:whs_code).first&.whs_code || Warehouse.order(:whs_code).first&.whs_code || "WH-MAIN"
    rows = [
      { seller_code: "SLR-001", name: "Juan Dela Cruz", branch_code: branch, status: "active", section: "KA",
        vcsi_sales_rep_ref: "538614", supervisor_name: "Supervisor A", gsm_name: "GSM A", om_name: "OM A",
        sales_target: "1500000", manager_codes: mgr, warehouse_code: wh, wms_enabled: "true",
        notes: "warehouse_code ties this seller to a warehouse; wms_enabled=true routes their orders through the WMS (pick/pack/dispatch) IF that warehouse also has WMS on — else blank/false keeps OSB batch download. vcsi_sales_rep_ref MUST match vcsi_rise." },
      { seller_code: "SLR-001-B", name: "Juan Dela Cruz (Branch 2)", branch_code: branch, status: "active",
        section: "HFS", vcsi_sales_rep_ref: "538615", sales_target: "0", primary_seller_code: "SLR-001",
        notes: "A rep's SECOND code -> set primary_seller_code to the main code to merge them into one login group (put the primary row first)." },
      { seller_code: "DSR-001", name: "Maria Santos", branch_code: branch, status: "active", section: "HFS",
        diser_code: "DIS-001", diser_name: "Maria (Diser)",
        notes: "diser_code sets the stock-check-only diser login (must differ from every seller_code). pin/diser_pin blank = keep the existing / shared PIN." },
    ]
    CSV.generate do |csv|
      csv << SELLER_HEADERS
      rows.each { |r| csv << SELLER_HEADERS.map { |h| r[h.to_sym] } }
    end
  end

  def product_channels_sample
    sku = Product.order(:id).first&.sku || "ITEMKEY-001"
    chan = Channel.order(:code).first&.code || "SARI"
    CSV.generate do |csv|
      csv << %w[item_key channel_code available]
      csv << [sku, chan, "true"]
      csv << [sku, chan, "false"] # example: remove a SKU from a channel
    end
  end

  def products_sample
    CSV.generate do |csv|
      csv << %w[itemkey desc1 desc2 brand_code category_code item_tier abc_class stock_uom purchase_uom selling_uom
                items_per_case items_per_shrinkwrap shrinkwraps_per_case casesperpallet layersperpallet casestatfactor
                caseheight caseweight casevolume it_barcode cs_barcode sw_barcode item_cost case_cost tax status]
      csv << ["KOP-3IN1-10S", "Kopiko Brown 3in1 10s", "", "KOPIKO", "COFFEE", "mainstream", "A", "PC", "CASE", "PC",
              "12", "6", "2", "80", "5", "1", "0.2500", "5.4000", "0.0180", "4800016641", "14800016641", "",
              "8.50", "102.00", "VAT", "active"]
    end
  end

  def stores_sample
    branch = Branch.order(:code).first&.code || "HQ"
    chan = Channel.order(:code).first&.code || "SARI"
    seller = Seller.order(:seller_code).first&.seller_code || "SLR-001"
    headers = %w[store_code name owner_name address contact_number latitude longitude branch_code channel_code
                 category status discount seller_code route_code route_name vcsi_customer_ref segment chain sub_chain
                 distribution_type tin visit_frequency week_pattern visit_day visit_sequence notes]
    rows = [
      { store_code: "ST-0001", name: "Aling Nena Store", owner_name: "Nena Cruz", address: "123 Rizal St, QC",
        contact_number: "09171234567", latitude: "14.6760", longitude: "121.0437", branch_code: branch, channel_code: chan,
        category: "silver", status: "active", discount: "2.5", seller_code: seller, route_code: "R-QC-01", route_name: "QC North", vcsi_customer_ref: "",
        visit_frequency: "f4", week_pattern: "every_week", visit_day: "mon", visit_sequence: "1",
        notes: "Weekly (F4) every Monday, 1st stop. discount 2.5 = 2.5% exclusive discount (ex-VAT). status active = shows in the app." },
      { store_code: "ST-0002", name: "7-Eleven Kamias", owner_name: "", address: "88 Kamias Rd, QC",
        contact_number: "", latitude: "14.6330", longitude: "121.0490", branch_code: branch, channel_code: chan,
        category: "gold", seller_code: seller, route_code: "R-QC-01", route_name: "QC North", vcsi_customer_ref: "",
        visit_frequency: "f2", week_pattern: "weeks_1_3", visit_day: "wed", visit_sequence: "2",
        notes: "Fortnightly (F2) weeks 1 & 3, Wednesday, 2nd stop." },
      { store_code: "ST-0003", name: "Mercury Drug Cubao", owner_name: "", address: "Cubao, QC",
        contact_number: "", latitude: "14.6190", longitude: "121.0510", branch_code: branch, channel_code: chan,
        category: "platinum", status: "inactive", seller_code: seller, route_code: "R-QC-02", route_name: "QC South", vcsi_customer_ref: "",
        visit_frequency: "f2", week_pattern: "weeks_2_4", visit_day: "fri", visit_sequence: "1",
        notes: "status inactive = HIDDEN from the seller app even though it still has a route (R-QC-02). Use active/inactive/closed. Blank keeps the current status." },
    ]
    CSV.generate do |csv|
      csv << headers
      rows.each { |r| csv << headers.map { |h| r[h.to_sym] } }
    end
  end

  # ---- WMS samples (pre-filled with real codes where possible) ----------------

  def warehouses_sample
    branch = Branch.order(:code).first&.code || "HQ"
    CSV.generate do |csv|
      csv << %w[whs_code wh_name branch_code address status wms_enabled allocation_strategy]
      csv << ["WH-MAIN", "Main Warehouse", branch, "123 Logistics Ave", "active", "true", "brand_per_picker"]
    end
  end

  def storage_locations_sample
    wh = Warehouse.order(:whs_code).first&.whs_code || "WH-MAIN"
    brand = Brand.order(:code).first&.code || "KOPIKO"
    rows = [
      { warehouse_code: wh, loc_code: "DOCK", name: "Receiving dock", zone: "DOCK", loc_type: "receiving_dock",
        pickable: "false", allow_mixed_lots: "true", slot_capacity: "9999", pick_sequence: "0",
        allowed_abc_classes: "", allowed_brand_codes: "", status: "active" },
      { warehouse_code: wh, loc_code: "A-01-01", name: "Aisle A Bay 1 Lvl 1", zone: "A", aisle: "A", bay: "01", level: "01",
        loc_type: "pick_rack", pickable: "true", allow_mixed_lots: "false", slot_capacity: "1", pick_sequence: "1",
        allowed_abc_classes: "A", allowed_brand_codes: brand, status: "active" },
      { warehouse_code: wh, loc_code: "BUF-01", name: "Buffer overflow", zone: "BUFFER", loc_type: "buffer",
        pickable: "false", allow_mixed_lots: "true", slot_capacity: "4", pick_sequence: "900",
        allowed_abc_classes: "", allowed_brand_codes: "", status: "active" },
      { warehouse_code: wh, loc_code: "HV-01", name: "High-value cage", zone: "HV", loc_type: "high_value",
        pickable: "true", allow_mixed_lots: "true", slot_capacity: "20", pick_sequence: "10",
        allowed_abc_classes: "", allowed_brand_codes: "", status: "active" },
    ]
    headers = %w[warehouse_code loc_code name zone aisle bay level loc_type pickable allow_mixed_lots
                 slot_capacity pick_sequence allowed_abc_classes allowed_brand_codes status]
    CSV.generate do |csv|
      csv << headers
      rows.each { |r| csv << headers.map { |h| r[h.to_sym] } }
    end
  end

  def inventory_sample
    wh = Warehouse.order(:whs_code).first&.whs_code || "WH-MAIN"
    sku = Product.order(:id).first&.sku || "KOP-3IN1-10S"
    bc = Product.where.not(it_barcode: [nil, ""]).order(:id).first&.it_barcode || "4800016641"
    CSV.generate do |csv|
      csv << %w[warehouse_code loc_code itemkey it_barcode lot_code received_date expiry_date qty_on_hand uom]
      csv << [wh, "A-01-01", sku, bc, "LOT-2026-10", "2026-10-01", "2027-10-01", "80", "case"]
    end
  end

  def asn_sample
    wh = Warehouse.order(:whs_code).first&.whs_code || "WH-MAIN"
    p = Product.where.not(it_barcode: [nil, ""]).order(:id).first
    sku = p&.sku || "KOP-3IN1-10S"
    bc = p&.it_barcode || "4800016641"
    CSV.generate do |csv|
      csv << %w[warehouse_code po_ref itemkey it_barcode expected_qty uom notes]
      csv << [wh, "PO-2026-1001", sku, bc, "80", "case",
              "itemkey (sku) is the KEY — it pins the exact item and travels with the stock to picking. " \
              "it_barcode is optional (taken from the product master if blank); the product's it_barcode scans loose/pieces and its cs_barcode scans cases. uom = case or pc."]
      csv << [wh, "PO-2026-1001", sku, bc, "24", "pc",
              "Same itemkey can arrive as loose pieces too — add a second line with uom=pc."]
    end
  end

  def dispatch_orders_sample
    wh = Warehouse.order(:whs_code).first&.whs_code || "WH-MAIN"
    store = Store.order(:store_code).first&.store_code || "ST-0001"
    bc  = Product.where.not(it_barcode: [nil, ""]).order(:id).first&.it_barcode || "4800016641"
    bc2 = Product.where.not(it_barcode: [nil, ""]).order(:id).offset(1).first&.it_barcode || bc
    today = Date.current
    CSV.generate do |csv|
      # Manual pick-job upload: identify the item by its BARCODE and give the
      # QUANTITY in pieces. The system finds the product, splits full cases from
      # the loose remainder, and FIFO resolves the itemkey (+ case barcode).
      csv << %w[warehouse_code reference_no store_code demand_date delivery_date remarks it_barcode quantity]
      # One pick job (reference_no) can have several item lines.
      csv << [wh, "DSP-0001", store, today, today + 1, "AM delivery only", bc, "120"]
      csv << [wh, "DSP-0001", store, today, today + 1, "", bc2, "30"]
    end
  end
end
