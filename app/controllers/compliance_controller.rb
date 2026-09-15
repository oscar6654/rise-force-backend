require "csv"

# Assortment (must-stock) compliance report — a per-seller summary (index) that
# drills into one seller's non-compliant stores (show). Derived live from
# Store#assortment_compliance (must-stock master vs what the store has ordered).
class ComplianceController < ApplicationController
  before_action -> { authorize!(:store, :view) }, only: [:index, :show, :download]

  DEFAULT_THRESHOLD = 100 # show stores below full compliance by default

  def index
    @filter_branches = filter_branches
    @threshold = threshold
    rows = compliance_rows(stores_scope)
    @total_with_assortment = rows.size
    below = rows.select { |r| r[:pct] < @threshold }
    @total_below = below.size

    groups = below.group_by { |r| r[:store].assigned_seller }.map do |seller, rs|
      { seller: seller, count: rs.size, avg: (rs.sum { |r| r[:pct] } / rs.size),
        worst: rs.min_by { |r| r[:pct] } }
    end
    groups.sort_by! { |g| [-g[:count], g[:seller]&.name || "~"] } # most gaps first, unassigned last
    @groups = Kaminari.paginate_array(groups).page(params[:page]).per(25)
  end

  def show
    @seller = find_seller!
    @threshold = threshold
    rows = compliance_rows(seller_stores(@seller)).select { |r| r[:pct] < @threshold }
                                                  .sort_by { |r| [r[:pct], -r[:must]] }
    @rows = Kaminari.paginate_array(rows).page(params[:page]).per(50)
    @gap_skus = gap_sku_map(@rows)
  end

  def download
    rows = compliance_rows(stores_scope).select { |r| r[:pct] < threshold }.sort_by { |r| r[:pct] }
    skus = gap_sku_map(rows)
    send_data csv_for(rows, skus), filename: "assortment_noncompliance_#{Date.current}.csv", type: "text/csv"
  end

  private

  def threshold
    (params[:threshold].presence || DEFAULT_THRESHOLD).to_i
  end

  # One row per active store (in the given scope) that has a must-stock assortment.
  # assortment_compliance runs a couple of queries per store, so callers scope it.
  def compliance_rows(scope)
    scope.filter_map do |s|
      c = s.assortment_compliance
      next if c.nil?

      { store: s, must: c[:must], carried: c[:carried], pct: c[:pct], gap_ids: c[:gap_product_ids] }
    end
  end

  def stores_scope
    scope = Store.where(status: :active).includes(:branch, :route, :store_category, :seller)
    scope = scope.where(branch_id: current_user.accessible_branch_ids) unless current_user.all_branches?
    scope = scope.where(branch_id: params[:branch_id]) if params[:branch_id].present?
    scope
  end

  # Stores whose assigned seller (direct seller_id, else route's seller) is this
  # seller — or, for the "unassigned" bucket, stores with no assigned seller.
  def seller_stores(seller)
    base = stores_scope
    if seller.nil?
      base.where(seller_id: nil).where("route_id IS NULL OR route_id IN (SELECT id FROM routes WHERE seller_id IS NULL)")
    else
      base.where("stores.seller_id = :s OR stores.route_id IN (SELECT id FROM routes WHERE seller_id = :s)", s: seller.id)
    end
  end

  def find_seller!
    return nil if params[:id] == "unassigned"

    seller = Seller.find(params[:id])
    authorize_branch!(seller)
    seller
  end

  def gap_sku_map(rows)
    ids = rows.flat_map { |r| r[:gap_ids] }.uniq
    ids.any? ? Product.where(id: ids).pluck(:id, :sku).to_h : {}
  end

  def filter_branches
    current_user.all_branches? ? Branch.order(:name) : Branch.where(id: current_user.accessible_branch_ids).order(:name)
  end

  def csv_for(rows, skus)
    CSV.generate do |csv|
      csv << %w[branch store_code store_name seller category must_stock carried compliance_pct missing_skus]
      rows.each do |r|
        s = r[:store]
        csv << [s.branch&.name, s.store_code, s.name, s.assigned_seller&.name, s.category,
                r[:must], r[:carried], r[:pct], r[:gap_ids].map { |id| skus[id] }.compact.join(" ")]
      end
    end
  end
end
