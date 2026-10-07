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

    stores = Store.where(id: store_ids).includes(:seller).index_by(&:id)
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
    {
      store_id: sid, name: store&.name || sid.to_s, code: store&.store_code, seller: store&.seller&.name,
      must: r[:must], done: r[:done], missing: r[:missing],
      pct: r[:must].positive? ? (r[:done] * 100.0 / r[:must]).round : 0,
    }
  end

  def display_store_detail(campaign, store)
    summary = DisplayReport.new(campaign, store_ids: [store.id]).by_store[store.id] ||
              { lines: [], must: 0, done: 0, missing: 0 }
    {
      campaign: { id: campaign.id, name: campaign.name, period_from: campaign.period_from, period_to: campaign.period_to },
      store: { store_id: store.id, name: store.name, code: store.store_code },
      must: summary[:must], done: summary[:done], missing: summary[:missing],
      lines: summary[:lines].map do |l|
        { promotion_name: l.promotion_name, category: l.category, brand: l.brand, executed: l.executed,
          photos: l.photos.map { |p| { image_url: p.image_url, taken_on: p.taken_on, activity_type: p.activity_type } } }
      end,
    }
  end
end
