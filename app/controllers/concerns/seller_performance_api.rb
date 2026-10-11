# Shared seller performance builders used by the manager app (drilling into a
# seller) and the seller app (viewing their own page). All parameterized by a
# set of seller ids (a login group) + month — no manager/seller specifics.
module SellerPerformanceApi
  extend ActiveSupport::Concern

  # Stores a group of sellers services (direct or via route), vcsi-linked.
  def group_stores(ids)
    Store.where(seller_id: ids)
         .or(Store.where(route_id: Route.where(seller_id: ids).select(:id)))
         .where.not(vcsi_customer_ref: [nil, ""])
  end

  def group_store_ids(ids)
    Store.where(seller_id: ids)
         .or(Store.where(route_id: Route.where(seller_id: ids).select(:id)))
         .pluck(:id)
  end

  # Pool each store's per-type compliance across the group's stores.
  def seller_assortment_by_type(ids)
    agg = {}
    Store.assortment_by_type_for(group_stores(ids).order(:id).limit(300)).each_value do |rows|
      rows.each do |row|
        a = (agg[row[:type_code]] ||= { type_name: row[:type_name], must: 0, carried: 0 })
        a[:must] += row[:must]
        a[:carried] += row[:carried]
      end
    end
    agg.map do |code, a|
      { type_code: code, type_name: a[:type_name], must: a[:must], carried: a[:carried],
        pct: (a[:must].positive? ? (a[:carried] * 100.0 / a[:must]).round : 0) }
    end
  end

  def seller_kpi(s, month)
    ids = s.login_group_ids
    confirmed = SelloutSnapshot.where(seller_id: ids, period_type: :mtd, period_date: month).sum(:amount)
    presell = Order.where(seller_id: ids).where.not(status: :cancelled)
                   .where(ordered_at: month.beginning_of_day..month.end_of_month.end_of_day).sum(:total_amount)
    target = SellerTarget.where(seller_id: ids, period_type: :mtd, period_date: month).sum(:target_amount).to_d
    blended = confirmed + presell
    {
      seller_id: s.id, name: s.name, branch: s.branch&.name,
      target_amount: target, confirmed_actual: confirmed, presell_pending: presell, blended_actual: blended,
      attainment_pct: (target.positive? ? (blended / target * 100).round : nil),
      pc_pct: s.route_productive_call_pct(month),
      active_stores: active_store_count(ids, month),
    }
  end

  def active_store_count(ids, month)
    store_ids = group_store_ids(ids)
    vcsi = Store.active_in_vcsi(month).where(id: store_ids).pluck(:id).to_set
    presell = Order.where(seller_id: ids, ordered_at: month..).where.not(status: :cancelled).distinct.pluck(:store_id).to_set
    (vcsi | presell).size
  end

  def store_perf(ids, month)
    store_ids = group_store_ids(ids)
    return [] if store_ids.empty?

    targets   = StoreTarget.for_month(month).where(store_id: store_ids).index_by(&:store_id)
    confirmed = SelloutSnapshot.where(store_id: store_ids, seller_id: nil, product_id: nil,
                                      period_type: :mtd, period_date: month).group(:store_id).sum(:amount)
    presell   = Order.where(store_id: store_ids).where.not(status: :cancelled)
                     .where(ordered_at: month.beginning_of_day..month.end_of_month.end_of_day)
                     .group(:store_id).sum(:total_amount)
    Store.where(id: store_ids).includes(:branch).order(:name).map do |st|
      conf = confirmed[st.id] || 0.to_d
      pre  = presell[st.id] || 0.to_d
      tgt  = targets[st.id]&.target_amount
      { store_id: st.id, name: st.name, code: st.code, branch: st.branch&.name,
        target_amount: tgt, confirmed_actual: conf, presell_pending: pre, blended_actual: conf + pre,
        attainment_pct: (tgt.to_d.positive? ? ((conf + pre) / tgt * 100).round : nil),
        active: conf.positive?, last_stock_checked_on: st.last_stock_checked_at&.to_date }
    end
  end
end
