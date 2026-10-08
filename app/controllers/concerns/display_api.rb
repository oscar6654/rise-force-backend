# Serializes display-target campaigns + per-store execution for the seller and
# manager apps. View-only: both read from the same DisplayReport matcher, scoped
# to the caller's store ids. Only campaigns live TODAY are returned.
module DisplayApi
  extend ActiveSupport::Concern

  # Resolve the stores a set of sellers (login group) services — by direct
  # ownership or via their routes.
  def display_store_ids_for(seller_ids)
    Store.where(seller_id: seller_ids)
         .or(Store.where(route_id: Route.where(seller_id: seller_ids).select(:id)))
         .pluck(:id)
  end

  def display_campaigns_payload(store_ids)
    store_ids = Array(store_ids)
    return [] if store_ids.empty?

    stores = Store.where(id: store_ids).includes(:seller, route: :seller).index_by(&:id)
    DisplayCampaign.active_on(Date.current).order(created_at: :desc).map do |c|
      rows = DisplayReport.new(c, store_ids: store_ids).by_store
                          .map { |sid, r| display_store_row(stores[sid], sid, r) }
                          .sort_by { |x| [-x[:missing], x[:name].to_s] }
      {
        id: c.id, name: c.name, period_from: c.period_from, period_to: c.period_to,
        must: rows.sum { |x| x[:must] }, done: rows.sum { |x| x[:done] },
        missing: rows.sum { |x| x[:missing] },
        stores: rows,
      }
    end
  end

  def display_store_row(store, sid, r)
    seller = store&.assigned_seller
    {
      store_id: sid, name: store&.name || sid.to_s, code: store&.store_code,
      seller: seller&.name, seller_id: seller&.id,
      must: r[:must], done: r[:done], missing: r[:missing],
      pct: r[:must].positive? ? (r[:done] * 100.0 / r[:must]).round : 0,
    }
  end

  # One store across ALL live campaigns (a store can have targets in several).
  def display_store_detail(store)
    campaigns = DisplayCampaign.active_on(Date.current).order(created_at: :desc).filter_map do |c|
      s = DisplayReport.new(c, store_ids: [store.id]).by_store[store.id]
      next if s.nil? || s[:must].zero?

      { id: c.id, name: c.name, period_from: c.period_from, period_to: c.period_to,
        must: s[:must], done: s[:done], missing: s[:missing],
        lines: s[:lines].map { |l| display_line_json(l) } }
    end
    {
      store: { store_id: store.id, name: store.name, code: store.store_code },
      must: campaigns.sum { |c| c[:must] }, done: campaigns.sum { |c| c[:done] },
      missing: campaigns.sum { |c| c[:missing] }, campaigns: campaigns,
    }
  end

  # { store_id => total missing lines across live campaigns } for route badges.
  def display_store_summary(store_ids)
    store_ids = Array(store_ids)
    return {} if store_ids.empty?

    totals = Hash.new(0)
    DisplayCampaign.active_on(Date.current).each do |c|
      DisplayReport.new(c, store_ids: store_ids).by_store.each { |sid, r| totals[sid] += r[:missing] }
    end
    totals
  end

  def display_line_json(l)
    { promotion_name: l.promotion_name, category: l.category, brand: l.brand, executed: l.executed,
      photos: l.photos.map { |p| { image_url: p.image_url, taken_on: p.taken_on, activity_type: p.activity_type } } }
  end
end
