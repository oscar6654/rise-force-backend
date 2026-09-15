module Api
  module V1
    # Store-scoped reads for the seller app: a consolidated profile, a
    # smart-start suggested order, and nearby-peer cross-sell recommendations.
    class StoresController < BaseController
      before_action :set_store, except: [:search]

      # GET /api/v1/stores/search?q=  — the seller's own stores (route + directly
      # assigned), for off-route "deviation" visits (e.g. revisiting a store that
      # was closed yesterday). Returns today's visit_status for color-coding.
      def search
        q = params[:q].to_s.strip
        return render json: { data: [], meta: meta } if q.length < 2

        stores = seller_stores.merge(Store.search(q)).order(:name).limit(20).to_a
        ids = stores.map(&:id)
        today = Date.current
        ordered = Order.where(seller: current_seller, store_id: ids).where.not(status: :cancelled)
                       .where(ordered_at: today.all_day).distinct.pluck(:store_id).to_set
        visited = Visit.where(seller: current_seller, store_id: ids, visit_date: today).distinct.pluck(:store_id).to_set

        rows = stores.map do |s|
          status = ordered.include?(s.id) ? "ordered" : visited.include?(s.id) ? "no_order" : "none"
          { store_id: s.id, name: s.name, code: s.code, latitude: s.latitude, longitude: s.longitude,
            on_route: s.route_id.present?, visit_status: status }
        end
        render json: { data: rows, meta: meta }
      end

      # GET /api/v1/stores/:id/profile
      # History + target/actual + must-stock gaps + compliance, in one call.
      def profile
        intel = SellerIntelligence.new(current_seller)
        month = Date.current.beginning_of_month
        compliance = @store.assortment_compliance
        gap_products = if compliance && compliance[:gap_product_ids].any?
                         Product.where(id: compliance[:gap_product_ids]).order(:sku)
                                .pluck(:sku, :description).map { |sku, d| { sku: sku, description: d } }
                       else
                         []
                       end

        # Per-assortment-type must-carry breakdown (a scorecard per type, not one
        # combined number). Only types with must-stock items for this store.
        by_type = AssortmentType.enabled.ordered.filter_map do |t|
          c = @store.assortment_compliance(type_code: t.code)
          next unless c && c[:must].positive?

          gaps = if c[:gap_product_ids].any?
                   Product.where(id: c[:gap_product_ids]).order(:sku)
                          .pluck(:sku, :description).map { |sku, d| { sku: sku, description: d } }
                 else
                   []
                 end
          { type_code: t.code, type_name: t.name, must: c[:must], carried: c[:carried], pct: c[:pct], gaps: gaps }
        end

        # For the Catalog type filter chips: which product_ids belong to each
        # assortment type for this store (the full must-stock set, not just gaps).
        type_skus = {}
        type_list = []
        AssortmentType.enabled.ordered.each do |t|
          ids = Assortment.resolved_items_for(@store, type_code: t.code).where(must_stock: true).distinct.pluck(:product_id)
          next if ids.empty?

          type_skus[t.code] = ids
          type_list << { code: t.code, name: t.name }
        end

        render json: {
          data: {
            store: { id: @store.id, name: @store.name, code: @store.code, category: @store.category, channel_id: @store.channel_id },
            target_amount: @store.target_for(month),
            confirmed_actual: @store.confirmed_actual(month),
            presell_pending: @store.pending_presell(month),
            blended_actual: @store.blended_actual(month),
            attainment_pct: @store.attainment_pct(month),
            active: @store.active_in_vcsi?(month),
            compliance: compliance && { must: compliance[:must], carried: compliance[:carried], pct: compliance[:pct] },
            compliance_by_type: by_type,
            assortment_type_skus: type_skus,        # { type_code => [product_id,…] } for filter chips
            assortment_types: type_list,            # [{ code, name }] present for this store
            must_stock_gaps: gap_products,
            suggested_order: intel.suggested_order(@store),
            cross_sell: intel.cross_sell(@store),
            next_best_action: intel.next_best_action(@store),
            predictive_reorder: intel.predictive_reorder(@store),
            recent_orders: recent_orders_json,
          },
          meta: meta,
        }
      end

      # GET /api/v1/stores/:id/prefill
      # Blended "last bought" quantities to prefill order-taking & stock check:
      # the store's most recent SFA presell (this cycle) wins per SKU, else the
      # vcsi_rise confirmed last-invoiced qty. Rows: product_id, sku, description,
      # qty, uom, source ("sfa"|"vcsi"), last_on.
      def prefill
        rows = {}

        # SFA most recent presell order = the base / fallback (fills SKUs vcsi
        # hasn't confirmed yet, e.g. a just-taken order not yet invoiced).
        last_order = Order.where(store: @store).where.not(status: :cancelled).order(ordered_at: :desc).first
        last_order&.order_lines&.includes(:product)&.each do |l|
          rep = prefill_representative(l.product)
          next unless rep

          rows[rep.id] = { product_id: rep.id, sku: rep.sku, description: rep.description,
                           qty: l.quantity, uom: l.uom, source: "sfa", last_on: last_order.ordered_at }
        end

        # vcsi confirmed last invoiced order WINS — the true source of what was
        # actually delivered. Mapped to the catalog representative per barcode.
        VcsiRise::Client.new.store_last_order(customer_id: @store.vcsi_customer_ref).each do |r|
          rep = Product.representative_for(r["it_barcode"].to_s)
          next unless rep

          rows[rep.id] = { product_id: rep.id, sku: rep.sku, description: rep.description,
                           qty: r["qty"].to_d, uom: (r["uom"].presence || "pc"),
                           source: "vcsi", last_on: r["ordered_on"] }
        end

        render json: { data: rows.values, meta: meta }
      end

      # Map a product to the SKU shown in the collapsed catalog (its barcode's
      # representative), so prefill quantities land on the row the seller sees.
      def prefill_representative(product)
        return nil unless product

        (product.it_barcode.present? && Product.representative_for(product.it_barcode)) || product
      end

      # GET /api/v1/stores/:id/suggested_order
      def suggested_order
        render json: { data: SellerIntelligence.new(current_seller).suggested_order(@store), meta: meta }
      end

      # GET /api/v1/stores/:id/cross_sell
      def cross_sell
        render json: { data: SellerIntelligence.new(current_seller).cross_sell(@store), meta: meta }
      end

      private

      def set_store
        @store = Store.find(params[:id])
      end

      # The seller's own stores: directly assigned or on one of their routes.
      def seller_stores
        Store.where(seller: current_seller)
             .or(Store.where(route_id: Route.where(seller: current_seller).select(:id)))
      end

      def recent_orders_json
        Order.where(store: @store).where.not(status: :cancelled).order(ordered_at: :desc).limit(3)
             .includes(order_lines: :product).map do |o|
          { ordered_at: o.ordered_at, total_amount: o.total_amount,
            lines: o.order_lines.map { |l| { sku: l.product&.sku, quantity: l.quantity, uom: l.uom } } }
        end
      end
    end
  end
end
