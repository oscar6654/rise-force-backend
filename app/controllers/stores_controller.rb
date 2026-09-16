class StoresController < ApplicationController
  before_action -> { authorize!(:store, :view) }, only: [:index, :show]
  before_action -> { authorize!(:store, :create) }, only: [:new, :create]
  before_action -> { authorize!(:store, :update) }, only: [:edit, :update]
  before_action :set_store, only: [:show, :edit, :update, :stock_report, :stock_history, :stock_offtake]

  def index
    scope = branch_scoped(Store.includes(:channel, :route, :branch, :seller, :store_category)).search(params[:q])
    scope = scope.where(channel_id: params[:channel_id]) if params[:channel_id].present?
    scope = scope.where(store_category_id: params[:category]) if params[:category].present?
    scope = scope.where("seller_id = :s OR route_id IN (SELECT id FROM routes WHERE seller_id = :s)", s: params[:seller_id]) if params[:seller_id].present?
    scope = scope.where(branch_id: params[:branch_id]) if params[:branch_id].present? && branch_filterable?
    @stores = scope.order(:name).page(params[:page]).per(25)
    @channels = Channel.order(:name)
  end

  def show
    @month = Date.current.beginning_of_month
    @store_target = StoreTarget.for_month(@month).find_by(store: @store)
    @confirmed = @store.confirmed_actual(@month)
    @pending_presell = @store.pending_presell(@month)
    @blended = @confirmed + @pending_presell
    @last_sellout_sync = SelloutSnapshot.store_last_synced_at(@store, month: @month)
    @attainment = @store.attainment_pct(@month)

    @compliance = @store.assortment_compliance
    if @compliance && @compliance[:gap_product_ids].any?
      @gap_products = Product.where(id: @compliance[:gap_product_ids]).order(:sku).pluck(:sku, :description)
    end

    # Stock-check intelligence: predicted inventory + ICO per SKU, and the
    # count timeline (date => SKUs counted) so the panel shows the history.
    est = StoreInventoryEstimator.new(@store)
    @inventory_rows = est.rows
    @last_stock_checked_on = est.last_checked_on
    @next_visit_on = est.next_visit_on
    @from = parse_date(params[:from])
    @to   = parse_date(params[:to])
    @stock_check_dates = count_history_scope(@store, @from, @to)
                         .group(Arel.sql("COALESCE(visits.visit_date, stock_counts.created_at::date)"))
                         .count
                         .sort_by { |d, _| d }.reverse
  end

  # GET /stores/:id/stock_history.csv?from=&to= — raw counts (date × SKU) to
  # analyze how the shelf moved over a period.
  def stock_history
    authorize!(:stock_count, :download)
    require "csv"
    rows = count_history_scope(@store, parse_date(params[:from]), parse_date(params[:to]))
           .order(Arel.sql("COALESCE(visits.visit_date, stock_counts.created_at::date) DESC"))
           .pluck(Arel.sql("COALESCE(visits.visit_date, stock_counts.created_at::date)"),
                  "products.sku", "products.description", "products.it_barcode",
                  "stock_counts.qty", "sellers.name")
    csv = CSV.generate do |out|
      out << ["Counted on", "SKU", "Description", "IT barcode", "Pieces on shelf", "Counted by"]
      rows.each { |date, sku, desc, bc, qty, seller| out << [date, sku, desc, bc, qty.to_i, seller] }
    end
    send_data csv, filename: "stock_history_#{@store.code}_#{Date.current.iso8601}.csv", type: "text/csv"
  end

  # GET /stores/:id/stock_offtake.csv?from=&to= — sell-through analytics: per SKU
  # total sold (offtake), delivered, and average daily rate over the range.
  def stock_offtake
    authorize!(:stock_count, :download)
    require "csv"
    rows = StoreInventoryEstimator.new(@store).offtake_analysis(from: parse_date(params[:from]), to: parse_date(params[:to]))
    csv = CSV.generate do |out|
      out << ["SKU", "Description", "IT barcode", "Counts", "First count", "Last count",
              "Delivered (est)", "Sold (offtake)", "Days", "Avg offtake/day"]
      rows.each do |r|
        out << [r.sku, r.description, r.it_barcode, r.counts, r.first_count_on, r.last_count_on,
                r.delivered, r.sold, r.days, r.avg_daily]
      end
    end
    send_data csv, filename: "offtake_#{@store.code}_#{Date.current.iso8601}.csv", type: "text/csv"
  end

  # GET /stores/:id/stock_report.csv — compiled stock-check + ICO report.
  def stock_report
    authorize!(:stock_count, :download)
    est = StoreInventoryEstimator.new(@store)
    send_data stock_report_csv(est),
              filename: "stock_report_#{@store.code}_#{Date.current.iso8601}.csv",
              type: "text/csv"
  end

  def new
    @store = Store.new(branch_id: default_branch_id, status: :active)
  end

  def create
    @store = Store.new(store_params)
    @store.branch_id ||= default_branch_id
    authorize_branch!(@store)
    if @store.save
      redirect_to stores_path, notice: "Store created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    authorize_branch!(@store)
    if @store.update(store_params)
      redirect_to store_path(@store), notice: "Store updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  DATE_EXPR = "COALESCE(visits.visit_date, stock_counts.created_at::date)".freeze

  def parse_date(str)
    str.present? ? Date.parse(str) : nil
  rescue ArgumentError
    nil
  end

  # Raw stock counts for a store, optionally within a counted-on date range.
  def count_history_scope(store, from, to)
    scope = StockCount.joins(:product, visit: :seller).where(visits: { store_id: store.id })
    scope = scope.where("#{DATE_EXPR} >= ?", from) if from
    scope = scope.where("#{DATE_EXPR} <= ?", to) if to
    scope
  end

  def stock_report_csv(est)
    require "csv"
    CSV.generate do |csv|
      csv << ["Store", @store.code, @store.name]
      csv << ["Last stock checked", est.last_checked_on]
      csv << ["Next scheduled visit", est.next_visit_on]
      csv << []
      csv << ["SKU", "Description", "IT barcode", "On hand (last count)", "Counted on",
              "Days since", "Delivered since (est)", "Offtake/day", "Predicted on hand",
              "Cover days", "Suggested pieces", "Suggested cases", "Basis"]
      est.rows.each do |r|
        csv << [r.sku, r.description, r.it_barcode, r.on_hand, r.checked_on, r.days_since_check,
                r.delivered_since, r.offtake_per_day, r.predicted_on_hand, r.cover_days,
                r.suggested_pieces, r.suggested_cases, r.basis]
      end
    end
  end

  def set_store
    @store = Store.find(params[:id])
    authorize_branch!(@store)
  end

  def store_params
    permitted = params.require(:store).permit(:store_code, :name, :owner_name, :contact_number,
                :address, :latitude, :longitude, :channel_id, :route_id, :seller_id, :category_code, :status,
                :visit_frequency, :week_pattern, :visit_day, :visit_sequence, :vcsi_customer_ref, :branch_id,
                :segment, :chain, :sub_chain, :distribution_type, :tin)
    # Branch-scoped users cannot reassign the branch.
    permitted[:branch_id] = current_user.branch_id if current_user.branch_scoped?
    permitted
  end
end
