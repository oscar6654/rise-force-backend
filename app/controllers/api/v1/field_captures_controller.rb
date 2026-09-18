module Api
  module V1
    # Idempotent (client_uuid) uploads for in-store capture: shelf stock counts,
    # competitor price checks, and planogram-compliance photos.
    class FieldCapturesController < BaseController
      # POST /api/v1/stock_counts
      #   Seller flow: { visit_client_uuid|visit_id, counts:[{client_uuid, product_id, qty}] }
      #     — a count is unique per (visit, product): re-counting UPDATES it.
      #   Diser flow: { store_id, counted_on, counts:[...] } — store-scoped, NO
      #     visit (so it never touches coverage); unique per (store, product, date).
      def stock_counts
        if params[:store_id].present?
          store = diser_store!(params[:store_id])
          return unless store

          counted_on = parse_date(params[:counted_on]) || Date.current
          results = upsert_counts(params[:counts]) do |c|
            StockCount.find_or_initialize_by(store_id: store.id, product_id: c[:product_id], counted_on: counted_on)
          end
          counted_at = counted_on.to_time
        else
          visit = find_visit
          store = visit.store
          results = upsert_counts(params[:counts]) { |c| StockCount.find_or_initialize_by(visit: visit, product_id: c[:product_id]) }
          counted_at = visit.started_at || visit.visit_date&.to_time || Time.current
        end

        # Stamp the store's last-checked time from WHEN it was counted (not sync
        # time), only ever moving forward — so an offline count syncing later
        # still shows the real count date.
        if results.any? && store && (store.last_stock_checked_at.nil? || store.last_stock_checked_at < counted_at)
          store.update_column(:last_stock_checked_at, counted_at)
        end
        render json: { data: { saved: results.size }, meta: meta }, status: :created
      end

      # GET /api/v1/stores/:id/last_stock_counts[?visit_client_uuid=]  (prefill)
      # With visit_client_uuid → that visit's own counts (resume the in-progress
      # count). Without → the store's most recent counted visit (last known shelf).
      def last_stock_counts
        store = Store.find(params[:id])
        rows =
          if params[:visit_client_uuid].present?
            visit = Visit.find_by(client_uuid: params[:visit_client_uuid], seller: current_seller)
            visit ? visit.stock_counts.map { |c| { product_id: c.product_id, qty: c.qty } } : []
          else
            # Most recent counted date for the store across BOTH grains (seller
            # visit or diser store-scoped) → that date's counts.
            last_date = StockCount.for_store(store.id).maximum(Arel.sql(StockCount::DATE_SQL))
            if last_date
              StockCount.for_store(store.id).where("#{StockCount::DATE_SQL} = ?", last_date)
                        .pluck("stock_counts.product_id", "stock_counts.qty")
                        .map { |pid, qty| { product_id: pid, qty: qty } }
            else
              []
            end
          end
        render json: { data: rows, meta: meta }
      end

      # POST /api/v1/competitor_checks { visit_id, items: [{ client_uuid, product_id?, product_label, our_price, competitor_name, competitor_price, notes }] }
      def competitor_checks
        visit = find_visit
        results = Array(params[:items]).map do |i|
          CompetitorPriceCheck.find_or_create_by!(client_uuid: i[:client_uuid]) do |chk|
            chk.visit = visit; chk.product_id = i[:product_id]; chk.product_label = i[:product_label]
            chk.our_price = i[:our_price]; chk.competitor_name = i[:competitor_name]
            chk.competitor_price = i[:competitor_price]; chk.notes = i[:notes]
          end
        end
        render json: { data: { saved: results.size }, meta: meta }, status: :created
      end

      # POST /api/v1/visit_photos (multipart) { client_uuid, visit_id, planogram_id?, kind, image }
      def visit_photos
        visit = find_visit
        photo = VisitPhoto.find_or_initialize_by(client_uuid: params.require(:client_uuid))
        if photo.new_record?
          photo.assign_attributes(visit: visit, planogram_id: params[:planogram_id], kind: params[:kind] || :planogram_compliance)
          photo.image.attach(params[:image]) if params[:image]
          photo.save!
        end
        render json: { data: { id: photo.id }, meta: meta }, status: :created
      end

      private

      # Upsert each count row via the block's find_or_initialize, keeping the
      # original client_uuid on update (idempotent replays).
      def upsert_counts(counts)
        Array(counts).map do |c|
          sc = yield(c)
          sc.client_uuid ||= c[:client_uuid]
          sc.qty = c[:qty].to_d
          sc.prefilled_from = c[:prefilled_from] || :none
          sc.save!
          sc
        end
      end

      # A diser may only count stores in the seller they assist (their route
      # stores or branch). Returns the store or renders 404 and nil.
      def diser_store!(id)
        store = Store.where(seller: current_seller)
                     .or(Store.where(route_id: Route.where(seller: current_seller).select(:id)))
                     .or(Store.where(branch_id: current_seller.branch_id))
                     .find_by(id: id)
        render(json: { error: { code: "not_found", message: "Store not in your coverage" } }, status: :not_found) unless store
        store
      end

      def parse_date(str)
        str.present? ? Date.parse(str) : nil
      rescue ArgumentError
        nil
      end

      # Offline-first: the app references the visit by its client_uuid (which it
      # has immediately), not the server id (assigned only after the check-in
      # syncs). Accept either.
      def find_visit
        if params[:visit_client_uuid].present?
          Visit.find_by!(client_uuid: params[:visit_client_uuid], seller: current_seller)
        else
          Visit.find_by!(id: params.require(:visit_id), seller: current_seller)
        end
      end
    end
  end
end
