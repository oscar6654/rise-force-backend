require "csv"

# Field-visit report — a per-seller summary (index) that drills into one seller's
# Store -> visits detail (show). Surfaces what the app captures on each call:
# off-route, GPS mismatch, geofence-override reason, and no-order reason.
class VisitsController < ApplicationController
  before_action -> { authorize!(:visit, :view) }, only: [:index, :show]
  before_action -> { authorize!(:visit, :download) }, only: [:download]

  # Per-seller summary. Counts are computed with grouped queries (not by loading
  # every visit), so the page is cheap no matter how many stores/visits exist.
  def index
    @filter_branches = filter_branches
    @sellers_filter = seller_options
    base = with_scope_filters(Visit.joins(store: :branch))
    r = geofence_radius

    totals   = base.group(:seller_id).count
    stores   = base.distinct.group(:seller_id).count(:store_id)
    off      = base.where(off_route: true).group(:seller_id).count
    no_order = base.where(status: :closed_no_order).group(:seller_id).count
    override = base.with_geofence_override.group(:seller_id).count
    mismatch = base.beyond_radius(r).group(:seller_id).count

    @summary = { visits: totals.values.sum, sellers: totals.size, off_route: off.values.sum,
                 no_order: no_order.values.sum, override: override.values.sum }

    sellers = Seller.where(id: totals.keys).includes(:branch).order(:name).to_a
    @sellers_page = Kaminari.paginate_array(sellers, total_count: sellers.size).page(params[:page]).per(25)
    @rows = @sellers_page.map do |s|
      { seller: s, visits: totals[s.id] || 0, stores: stores[s.id] || 0, off_route: off[s.id] || 0,
        no_order: no_order[s.id] || 0, override: override[s.id] || 0, gps_mismatch: mismatch[s.id] || 0 }
    end
  end

  # One seller's detail: their visits grouped by store (stores paginated), with
  # the flag chips filtering this seller's visits.
  def show
    @seller = Seller.find(params[:id])
    authorize_branch!(@seller)
    scoped = apply_flag(seller_scope(@seller), params[:flag])
    r = geofence_radius

    unfiltered = seller_scope(@seller)
    @tallies = {
      all: unfiltered.count,
      off_route: unfiltered.where(off_route: true).count,
      no_order: unfiltered.where(status: :closed_no_order).count,
      geofence_override: unfiltered.with_geofence_override.count,
      gps_mismatch: unfiltered.beyond_radius(r).count
    }

    store_ids = scoped.reorder(nil).distinct.pluck(:store_id)
    stores = Store.where(id: store_ids).order(:name).to_a
    @stores_page = Kaminari.paginate_array(stores, total_count: store_ids.size).page(params[:page]).per(25)
    page_visits = scoped.where(store_id: @stores_page.map(&:id))
                        .includes(:store).order(Arel.sql("visits.started_at DESC NULLS LAST"))
    @by_store = page_visits.group_by(&:store_id)
    @visit_count = scoped.count
  end

  def download
    scope = filtered.order(Arel.sql("visits.started_at DESC NULLS LAST"))
    send_data csv_for(scope), filename: "visits_#{Date.current}.csv", type: "text/csv"
  end

  private

  # Full CSV honours branch/seller/date/flag filters from either screen.
  def filtered
    scope = with_scope_filters(Visit.joins(store: :branch).includes(:seller, :route, store: :branch))
    scope = scope.where(seller_id: params[:seller_id]) if params[:seller_id].present?
    apply_flag(scope, params[:flag])
  end

  def seller_scope(seller)
    with_date_range(Visit.joins(store: :branch).where(seller_id: seller.id), "visits.visit_date")
  end

  # Branch/seller/date filters shared by the summary counts and the CSV.
  def with_scope_filters(scope)
    scope = scope.where(stores: { branch_id: current_user.accessible_branch_ids }) unless current_user.all_branches?
    scope = scope.where(stores: { branch_id: params[:branch_id] }) if params[:branch_id].present?
    scope = scope.where(seller_id: params[:seller_id]) if params[:seller_id].present? && action_name != "index"
    with_date_range(scope, "visits.visit_date")
  end

  def apply_flag(scope, flag)
    case flag
    when "off_route"         then scope.where(off_route: true)
    when "no_order"          then scope.where(status: :closed_no_order)
    when "geofence_override" then scope.with_geofence_override
    when "gps_mismatch"      then scope.beyond_radius(geofence_radius)
    else scope
    end
  end

  def geofence_radius
    @geofence_radius ||= SystemSetting.get("checkin_geofence_radius_m", 150).to_i
  end

  def with_date_range(scope, column)
    if params[:from].present?
      scope = scope.where("#{column} >= ?", Date.parse(params[:from])) rescue scope
    end
    if params[:to].present?
      scope = scope.where("#{column} <= ?", Date.parse(params[:to])) rescue scope
    end
    scope
  end

  def filter_branches
    current_user.all_branches? ? Branch.order(:name) : Branch.where(id: current_user.accessible_branch_ids).order(:name)
  end

  def seller_options
    scope = Seller.order(:name)
    scope = scope.where(branch_id: current_user.accessible_branch_ids) unless current_user.all_branches?
    scope
  end

  def csv_for(scope)
    CSV.generate do |csv|
      csv << %w[branch store_code store_name seller visit_date started_at ended_at
                outcome no_order_reason off_route distance_m geofence_override_reason]
      scope.find_each do |v|
        csv << [v.store&.branch&.name, v.store&.store_code, v.store&.name, v.seller&.name,
                v.visit_date, v.started_at&.iso8601, v.ended_at&.iso8601,
                v.status, v.no_order_reason, v.off_route,
                v.gps_mismatch_distance_m, v.geofence_reason]
      end
    end
  end
end
