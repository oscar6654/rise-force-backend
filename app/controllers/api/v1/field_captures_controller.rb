module Api
  module V1
    # Idempotent (client_uuid) uploads for in-store capture: shelf stock counts,
    # competitor price checks, and planogram-compliance photos.
    class FieldCapturesController < BaseController
      # POST /api/v1/stock_counts { visit_id, counts: [{ client_uuid, product_id, qty, prefilled_from? }] }
      # A stock count is unique per (visit, product): re-counting a SKU UPDATES it
      # rather than inserting a duplicate (which the unique index would reject).
      def stock_counts
        visit = find_visit
        results = Array(params[:counts]).map do |c|
          sc = StockCount.find_or_initialize_by(visit: visit, product_id: c[:product_id])
          sc.client_uuid ||= c[:client_uuid] # keep the original on update
          sc.qty = c[:qty].to_d
          sc.prefilled_from = c[:prefilled_from] || :none
          sc.save!
          sc
        end
        # Stamp the store's last-checked time so the console/list and the
        # inventory engine can find the freshest shelf read without a scan.
        visit.store&.update_column(:last_stock_checked_at, Time.current) if results.any?
        render json: { data: { saved: results.size }, meta: meta }, status: :created
      end

      # GET /api/v1/stores/:id/last_stock_counts[?visit_client_uuid=]  (prefill)
      # With visit_client_uuid → that visit's own counts (resume the in-progress
      # count). Without → the store's most recent counted visit (last known shelf).
      def last_stock_counts
        store = Store.find(params[:id])
        visit =
          if params[:visit_client_uuid].present?
            Visit.find_by(client_uuid: params[:visit_client_uuid], seller: current_seller)
          else
            # Most recent visit that actually has counts (not just the latest visit).
            Visit.where(seller: current_seller, store: store)
                 .where(id: StockCount.select(:visit_id))
                 .order(started_at: :desc).first
          end
        rows = visit ? visit.stock_counts.map { |c| { product_id: c.product_id, qty: c.qty } } : []
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
