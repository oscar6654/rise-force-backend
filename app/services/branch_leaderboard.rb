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
    # A login group ranks as ONE entrant (the primary/login record); its metric
    # aggregates across every seller record in the group.
    my_group = @seller.login_group_ids
    rows = @sellers.map do |s|
      { seller_id: s.id, name: s.name, value: value_for(s, metric, assortment_type),
        me: s.login_group_ids.include?(@seller.id) || my_group.include?(s.id) }
    end
    rows.sort_by! { |r| -r[:value] }
    rows.each_with_index { |r, i| r[:rank] = i + 1 }
    { metric: metric, assortment_type: assortment_type, rows: rows,
      me_rank: rows.find { |r| r[:me] }&.dig(:rank), of: rows.size,
      # Branch context so the app can render the branch filter chips.
      branch: @branch.presence || "mine", my_branch_id: @seller.branch_id,
      branches: Branch.active.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } } }
  end

  private

  def seller_scope
    # Only login records (primary / standalone) are entrants; secondary records
    # of a login group roll into their primary, so a group appears once.
    scope = Seller.active.where(primary_seller_id: nil)
    case @branch
    when "", nil     then scope.where(branch_id: @seller.branch_id) # default: own branch
    when "all", "total" then scope                                  # every branch
    else scope.where(branch_id: @branch.to_i)                       # a specific branch
    end
  end

  # Metrics aggregate across the entrant's whole login group.
  def value_for(seller, metric, assortment_type = nil)
    ids = seller.login_group_ids
    case metric
    when 'target_pct'
      t = SellerTarget.where(seller_id: ids, period_type: :mtd, period_date: @month).sum(:target_amount).to_d
      t.positive? ? (SelloutSnapshot.where(seller_id: ids, period_type: :mtd, period_date: @month).sum(:amount) / t * 100).round : 0
    when 'productive_call_pct'
      # Month-running: scheduled route store-days ordered / total scheduled, so
      # 1 of 8 due today reads 13% and climbs as the month accumulates.
      Seller.route_pc_for_ids(ids, @month) || 0
    when 'incentive'
      ids.sum { |sid| IncentiveCalculator.new(Seller.find(sid), month: @month).call[:confirmed_total].to_i }
    when 'assortment'
      assortment_score(ids, assortment_type)
    end
  end

  # Distribution width POOLED across all the group's stores: total barcodes
  # carried / total must-stock barcodes, as a percentage. A single store rarely
  # hits 100%, so pooling every store gives a fair running figure — e.g. 1/86 at
  # one store and 0/86 at another reads 1 / 172 ≈ 1%. `type_code` scopes to one
  # assortment type; nil = all types merged.
  def assortment_score(ids, type_code = nil)
    stores = Store.where(seller_id: ids).or(Store.where(route_id: Route.where(seller_id: ids).select(:id)))
                  .where.not(vcsi_customer_ref: [nil, '']).limit(300)
    must = 0
    carried = 0
    stores.each do |s|
      c = s.assortment_compliance(type_code: type_code)
      next unless c

      must += c[:must]
      carried += c[:carried]
    end
    must.positive? ? (carried * 100.0 / must).round : 0
  end
end
