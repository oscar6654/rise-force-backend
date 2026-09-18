module Api
  module V1
    class OrdersController < BaseController
      # A diser (stock-check-only role) may never take or preview orders.
      before_action :deny_diser!, only: [:create, :preview]

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

        # Login group: attribute the order to the seller record that OWNS this
        # store (its branch / vcsi rep code), so OSB batches + confirmed sellout
        # line up — even though the login may be another group member.
        os = store.assigned_seller
        order_seller = (os && current_group_ids.include?(os.id)) ? os : current_seller

        resolver = PricingResolver.new
        order = nil
        Order.transaction do
          order = Order.create!(
            client_uuid: uuid, seller: order_seller, store: store, branch: store.branch,
            route: store.route, pricing_version_id: resolver.version&.id,
            ordered_at: params[:ordered_at] || Time.current, synced_at: Time.current,
            status: :submitted, notes: params[:notes]
          )
          Array(params[:lines]).each { |line| build_line(order, store, resolver, line) }
          order.recompute_total!
          apply_invoice_totals(order, store)
          link_visit(order)
        end
        render json: { data: order_json(order), meta: meta }, status: :created
      end

      # GET /api/v1/stores/:id/order_history?limit=3  (smart-start prefill)
      def history
        store = Store.find(params[:id])
        orders = Order.where(store: store, seller_id: current_group_ids).order(ordered_at: :desc)
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

      # Recompute the store's exclusive discount + promos EX-VAT, then VAT, and
      # store the invoice breakdown on the order so total_amount is the real
      # amount due (matches the app's order summary and what vcsi_rise invoices).
      def apply_invoice_totals(order, store)
        inputs = order.order_lines.where(line_type: :sale)
                      .map { |l| { product_id: l.product_id, quantity: l.quantity, uom: l.uom } }
        b = PromoEngine.new(store).preview(inputs)
        order.update!(
          total_amount: b[:total],
          promo_summary: b.slice(:subtotal, :amount_ex_vat, :store_discount_rate, :store_discount,
                                 :promo_savings, :promo_breakdown, :vatable_sales, :vat_rate, :vat, :total)
        )
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

      # Link the order to the visit it was taken on. The app knows the visit by
      # its client_uuid (it never has the server id), so match on that first; keep
      # visit_id as a fallback. We only set the association — the visit's status is
      # set at checkout (or by housekeeping), so a still-in-progress visit isn't
      # prematurely closed. If checkout already mis-marked it no-order (order not
      # yet synced), correct it to with-order now.
      def link_visit(order)
        visit = order_visit
        return unless visit

        order.update!(visit: visit, route: visit.route || order.route)
        visit.update!(status: :closed_with_order, no_order_reason: nil) if visit.closed_no_order?
      end

      def order_visit
        if params[:visit_client_uuid].present?
          Visit.find_by(client_uuid: params[:visit_client_uuid], seller: current_seller)
        elsif params[:visit_id].present?
          Visit.find_by(id: params[:visit_id], seller: current_seller)
        end
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
