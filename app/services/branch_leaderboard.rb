# Ranks the sellers in a branch on one metric so they can compete. Computed per
# metric (the app asks for the tab it's showing) to keep each call light.
# Metrics: target_pct, productive_call_pct, assortment, incentive.
class BranchLeaderboard
  METRICS = %w[target_pct productive_call_pct assortment incentive].freeze

  # `branch`: nil/"" = the seller's own branch (default), "all" = every branch
  # (total), or a specific branch id.
  def initialize(seller, month: Date.current.beginning_of_month, branch: nil)
    @seller = seller
    @month = month
    @branch = branch.to_s
    @sellers = seller_scope.to_a
  end

  # `assortment_type` (a type code) narrows the assortment metric to one type;
  # nil ranks on the merged all-types must-stock. Ignored for other metrics.
  def ranking(metric, assortment_type: nil)
    metric = 'target_pct' unless METRICS.include?(metric)
    rows = @sellers.map { |s| { seller_id: s.id, name: s.name, value: value_for(s, metric, assortment_type) } }
    rows.sort_by! { |r| -r[:value] }
    rows.each_with_index { |r, i| r[:rank] = i + 1; r[:me] = (r[:seller_id] == @seller.id) }
    { metric: metric, assortment_type: assortment_type, rows: rows,
      me_rank: rows.find { |r| r[:me] }&.dig(:rank), of: rows.size,
      # Branch context so the app can render the branch filter chips.
      branch: @branch.presence || "mine", my_branch_id: @seller.branch_id,
      branches: Branch.active.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } } }
  end

  private

  def seller_scope
    scope = Seller.active
    case @branch
    when "", nil     then scope.where(branch_id: @seller.branch_id) # default: own branch
    when "all", "total" then scope                                  # every branch
    else scope.where(branch_id: @branch.to_i)                       # a specific branch
    end
  end

  def value_for(seller, metric, assortment_type = nil)
    case metric
    when 'target_pct'
      t = seller.target_for(@month).to_d
      t.positive? ? (seller.confirmed_actual(@month) / t * 100).round : 0
    when 'productive_call_pct'
      seller.productive_call_pct(@month..Date.current) || 0
    when 'incentive'
      IncentiveCalculator.new(seller, month: @month).call[:confirmed_total].to_i
    when 'assortment'
      assortment_score(seller, assortment_type)
    end
  end

  # Count of the seller's linked stores with full must-stock. `type_code` scopes
  # to one assortment type; nil = all types merged.
  def assortment_score(seller, type_code = nil)
    stores = Store.where(seller: seller).or(Store.where(route_id: Route.where(seller: seller).select(:id)))
                  .where.not(vcsi_customer_ref: [nil, '']).limit(300)
    stores.count { |s| (c = s.assortment_compliance(type_code: type_code)) && c[:must].positive? && c[:carried] >= c[:must] }
  end
end
