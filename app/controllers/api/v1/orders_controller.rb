module Api
  module V1
    class OrdersController < BaseController
      # POST /api/v1/orders/preview
      # Same body as create, but computes price + earned promo lines + totals +
      # threshold nudges WITHOUT saving — so the app can show the deal live as
      # the seller builds the basket.
      def preview
        store = Store.find(params.require(:store_id))
        result = PromoEngine.new(store).preview(order_line_inputs)
        render json: { data: result, meta: meta }
      end

      # POST /api/v1/orders
      # { client_uuid, store_id, visit_id?, ordered_at, notes,
      #   lines: [{ product_id, quantity, uom, line_type?, promo_id? }] }
      # Idempotent on client_uuid; server resolves prices (client prices ignored).
      def create
        uuid = params.require(:client_uuid)
        existing = Order.find_by(client_uuid: uuid)
        return render(json: { data: order_json(existing), meta: meta }, status: :ok) if existing

        store = Store.find(params.require(:store_id))

        # Backstop: enforce per-store promo availment limits (the app should
        # pre-check from the synced limit + local history; this is authoritative).
        if (blocked = promo_limit_violation(store)).present?
          return render(json: { error: { code: "promo_limit_reached", message: blocked } },
                        status: :unprocessable_entity)
        end

        resolver = PricingResolver.new
        order = nil
        Order.transaction do
          order = Order.create!(
            client_uuid: uuid, seller: current_seller, store: store, branch: store.branch,
            route: store.route, pricing_version_id: resolver.version&.id,
            ordered_at: params[:ordered_at] || Time.current, synced_at: Time.current,
            status: :submitted, notes: params[:notes]
          )
          Array(params[:lines]).each { |line| build_line(order, store, resolver, line) }
          order.recompute_total!
          link_visit(order)
        end
        render json: { data: order_json(order), meta: meta }, status: :created
      end

      # GET /api/v1/stores/:id/order_history?limit=3  (smart-start prefill)
      def history
        store = Store.find(params[:id])
        orders = Order.where(store: store, seller: current_seller).order(ordered_at: :desc)
                      .limit((params[:limit] || 3).to_i).includes(order_lines: :product)
        rows = orders.map do |o|
          { ordered_at: o.ordered_at,
            lines: o.order_lines.map { |l| { product_id: l.product_id, sku: l.product.sku, quantity: l.quantity, uom: l.uom } } }
        end
        render json: { data: rows, meta: meta }
      end

      private

      def order_line_inputs
        Array(params[:lines]).map do |l|
          { product_id: l[:product_id], quantity: l[:quantity], uom: normalize_uom(l[:uom]) }
        end
      end

      # The app sends "case"/"pc"; the OrderLine enum is pc/case_uom. Accept both.
      def normalize_uom(value)
        value.to_s == "pc" ? "pc" : "case_uom"
      end

      # Returns a message if any promo referenced by this order has hit its
      # per-store availment limit, else nil. One order = one avail per promo.
      def promo_limit_violation(store)
        promo_ids = Array(params[:lines]).map { |l| l[:promo_id] }.compact.uniq
        return nil if promo_ids.empty?

        Promo.where(id: promo_ids).each do |promo|
          next if promo.available_for?(store)

          return "#{promo.name} can only be availed #{promo.per_store_limit}× per store for this promo period."
        end
        nil
      end

      def build_line(order, store, resolver, line)
        product = Product.find(line[:product_id])
        free = line[:line_type].to_s == "promo_free_good"
        uom = normalize_uom(line[:uom])
        rate = resolver.markup_rate(store.store_category_id, product.product_tier_id) || 0
        cost = resolver.cost_for(product, uom) || 0
        unit = free ? 0 : (resolver.price_for(store.store_category, product, uom: uom) || cost)
        order.order_lines.create!(
          product: product, promo_id: line[:promo_id], line_type: (free ? :promo_free_good : :sale),
          quantity: line[:quantity].to_d, uom: uom,
          base_price: cost, markup_rate: rate, unit_price: unit,
          vcsi_product_ref: product.vcsi_product_ref
        )
      end

      def link_visit(order)
        return if params[:visit_id].blank?

        visit = Visit.find_by(id: params[:visit_id], seller: current_seller)
        return unless visit

        order.update!(visit: visit, route: visit.route || order.route)
        visit.update(status: :closed_with_order)
      end

      def order_json(order)
        { id: order.id, client_uuid: order.client_uuid, order_number: order.order_number,
          status: order.status, total_amount: order.total_amount,
          lines: order.order_lines.map { |l| { product_id: l.product_id, quantity: l.quantity,
            uom: l.uom, unit_price: l.unit_price, line_type: l.line_type, line_total: l.line_total } } }
      end
    end
  end
end
