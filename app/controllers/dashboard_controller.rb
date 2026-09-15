class DashboardController < ApplicationController
  def index
    authorize!(:dashboard, :view)
    @month = Date.current.beginning_of_month
    branches = current_user.accessible_branch_ids

    stores  = Store.where(branch_id: branches)
    sellers = Seller.where(branch_id: branches)
    orders  = Order.where(branch_id: branches)

    # Productive calls (completed visits) MTD, branch-wide.
    visit_range = @month..Date.current.end_of_day
    completed_calls = Visit.for_branches(branches).where(visit_date: visit_range, status: [:closed_with_order, :closed_no_order]).count
    productive_calls = Visit.for_branches(branches).where(visit_date: visit_range, status: :closed_with_order).count

    # vcsi_rise actual sellout MTD (source of truth) across the seller-grain
    # snapshots — the headline number the seller app also shows as "confirmed".
    actual_sellout_mtd = SelloutSnapshot.period_mtd
                                        .where(period_date: @month, seller_id: sellers.select(:id))
                                        .sum(:amount)
    @last_sellout_sync = SelloutSnapshot.period_mtd.where(period_date: @month, seller_id: sellers.select(:id)).maximum(:synced_at)

    @kpis = {
      registered_stores: stores.where(status: :active).count,
      invoiced_stores: stores.active_in_vcsi(@month).count, # actually buying (vcsi_rise truth)
      sellers: sellers.where(status: :active).count,
      productive_call_pct: completed_calls.positive? ? (productive_calls * 100 / completed_calls) : nil,
      orders_mtd: orders.where(ordered_at: @month..).count,
      presell_mtd: orders.where(ordered_at: @month..).sum(:total_amount),
      actual_sellout_mtd: actual_sellout_mtd
    }

    @attention = [
      { title: "Store registrations pending", sub: "Field submissions to review",
        count: StoreRegistration.where(branch_id: branches).pending.count, path: store_registrations_path },
      { title: "Orders awaiting batching", sub: "Unbatched, ready for OSB",
        count: orders.unbatched.count, path: order_batches_path },
      { title: "Sellers with stale sync", sub: "No sync in 24h",
        count: sellers.select(&:sync_stale?).size, path: sellers_path }
    ]

    # Seller target attainment MTD: vcsi_rise target vs vcsi_rise actual sellout,
    # alongside SFA presell (this app's own orders).
    targets = SellerTarget.for_month(@month).where(seller_id: sellers.select(:id)).index_by(&:seller_id)
    actuals = SelloutSnapshot.period_mtd.where(period_date: @month, seller_id: sellers.select(:id))
                             .group(:seller_id).sum(:amount)
    presell = orders.where(ordered_at: @month..).group(:seller_id).sum(:total_amount)

    @attainment = sellers.includes(:branch).map do |s|
      target = targets[s.id]&.target_amount || 0
      actual = actuals[s.id] || 0
      { seller: s, target: target, actual: actual, presell: presell[s.id] || 0,
        pct: target.positive? ? (actual / target * 100).round : nil,
        last_sync: s.last_sync_at }
    end.sort_by { |r| -(r[:pct] || -1) }.first(12)
  end
end
