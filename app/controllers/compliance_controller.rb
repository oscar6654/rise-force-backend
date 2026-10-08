require "csv"

# Assortment (must-stock) compliance report — a per-seller summary (index) that
# drills into one seller's non-compliant stores (show). Derived live from
# Store.assortment_compliance_for (must-stock master vs what the store has ordered).
class ComplianceController < ApplicationController
  before_action -> { authorize!(:store, :view) }, only: [:index, :show, :download]

  DEFAULT_THRESHOLD = 100 # show stores below full compliance by default
  SELLERS_PER_PAGE = 10
  DOWNLOAD_BATCH = 1000

  # Paginated by seller (alphabetical) so a page only computes compliance for
  # that page's sellers' stores — computing all ~16k stores per request hung
  # every Puma thread.
  def index
    @filter_branches = filter_branches
    @threshold = threshold
    @sellers = Kaminari.paginate_array(seller_bucket_ids).page(params[:page]).per(SELLERS_PER_PAGE)
    page_ids = @sellers.to_a
    sellers = Seller.includes(:branch).where(id: page_ids.compact).index_by(&:id)

    rows = compliance_rows(stores_for_sellers(page_ids))
    by_seller = rows.group_by { |r| r[:store].assigned_seller&.id }
    @total_with_assortment = rows.size
    @total_below = 0

    @groups = page_ids.map do |sid|
      below = (by_seller[sid] || []).select { |r| r[:pct] < @threshold }
      @total_below += below.size
      { seller: sellers[sid], seller_id: sid, total: (by_seller[sid] || []).size, count: below.size,
        avg: below.any? ? (below.sum { |r| r[:pct] } / below.size) : nil,
        worst: below.min_by { |r| r[:pct] } }
    end
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
    rows = []
    stores_scope.find_in_batches(batch_size: DOWNLOAD_BATCH) do |batch|
      rows.concat(compliance_rows(batch).select { |r| r[:pct] < threshold })
    end
    rows.sort_by! { |r| r[:pct] }
    skus = gap_sku_map(rows)
    send_data csv_for(rows, skus), filename: "assortment_noncompliance_#{Date.current}.csv", type: "text/csv"
  end

  private

  def threshold
    (params[:threshold].presence || DEFAULT_THRESHOLD).to_i
  end

  # One row per store (in the given list) that has a must-stock assortment.
  def compliance_rows(stores)
    stores = stores.to_a
    results = Store.assortment_compliance_for(stores)
    stores.filter_map do |s|
      c = results[s.id]
      next if c.nil?

      { store: s, must: c[:must], carried: c[:carried], pct: c[:pct], gap_ids: c[:gap_product_ids] }
    end
  end

  def base_stores
    scope = Store.where(status: :active)
    scope = scope.where(branch_id: current_user.accessible_branch_ids) unless current_user.all_branches?
    scope = scope.where(branch_id: params[:branch_id]) if params[:branch_id].present?
    scope
  end

  def stores_scope
    base_stores.includes(:branch, :store_category, :seller, route: :seller)
  end

  # Seller ids that own at least one store in scope, alphabetical; nil (the
  # "unassigned" bucket) last if any store has no assigned seller.
  def seller_bucket_ids
    direct = base_stores.where.not(seller_id: nil).distinct.pluck(:seller_id)
    via_route = base_stores.where(seller_id: nil).joins(:route).where.not(routes: { seller_id: nil })
                           .distinct.pluck("routes.seller_id")
    ids = Seller.where(id: direct | via_route).order(:name, :id).pluck(:id)
    ids << nil if unassigned_stores(base_stores).exists?
    ids
  end

  # Stores whose assigned seller (direct seller_id, else route's seller) is one
  # of `seller_ids` (nil = the unassigned bucket).
  def stores_for_sellers(seller_ids)
    ids = seller_ids.compact
    scope = stores_scope.where("stores.seller_id IN (:ids) OR (stores.seller_id IS NULL AND " \
                               "stores.route_id IN (SELECT id FROM routes WHERE seller_id IN (:ids)))", ids: ids.presence || [0])
    scope = scope.or(unassigned_stores(stores_scope)) if seller_ids.include?(nil)
    scope
  end

  def seller_stores(seller)
    stores_for_sellers([seller&.id])
  end

  def unassigned_stores(scope)
    scope.where(seller_id: nil).where("stores.route_id IS NULL OR stores.route_id IN (SELECT id FROM routes WHERE seller_id IS NULL)")
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
