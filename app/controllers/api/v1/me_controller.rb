module Api
  module V1
    class MeController < BaseController
      # GET /api/v1/me/targets?period=mtd
      def targets
        month = Date.current.beginning_of_month
        target = SellerTarget.find_by(seller: current_seller, period_type: :mtd, period_date: month)&.target_amount || 0
        actual = SelloutSnapshot.mtd_actual_for(current_seller, month: month)
        # "To invoice" = value of SFA presell orders taken this month, pending OSB
        # invoicing. Distinct from vcsi_rise confirmed sellout (mostly non-SFA, can
        # be negative), so NOT reconciled against it — just what the seller ordered.
        presell = Order.where(seller: current_seller).where.not(status: :cancelled)
                       .where(ordered_at: month.beginning_of_day..month.end_of_month.end_of_day)
                       .sum(:total_amount)
        render json: { data: {
          period: month, target_amount: target, actual_amount: actual, presell_amount: presell,
          attainment_pct: (target.positive? ? (actual / target * 100).round : nil),
          last_sync_at: current_seller.last_sync_at
        }, meta: meta }
      end

      # GET /api/v1/me/summary  (field-app day-plan tiles)
      def summary
        today = Date.current
        month = today.beginning_of_month
        seller = current_seller
        planned = Store.joins(:route).where(routes: { seller_id: seller.id }).select { |s| s.due_on?(today) }
        planned_ids = planned.map(&:id)
        visited = Visit.where(seller: seller, visit_date: today).distinct.count(:store_id)
        # Route completion counts only PLANNED stores visited (off-route
        # deviations don't inflate the day's goal).
        visited_planned = planned_ids.any? ? Visit.where(seller: seller, visit_date: today, store_id: planned_ids).distinct.count(:store_id) : 0
        seller_store_ids = Store.joins(:route).where(routes: { seller_id: seller.id }).select(:id)
        # Active stores (BLENDED): a store buying in vcsi_rise this month
        # (confirmed) OR with a presell order this month (to-invoice) — the same
        # confirmed+presell model as the sales number.
        active_vcsi = Store.active_in_vcsi(month).where(id: seller_store_ids).pluck(:id).to_set
        active_presell = Order.where(seller: seller, ordered_at: month..).where.not(status: :cancelled)
                              .distinct.pluck(:store_id).to_set
        active_stores = (active_vcsi | active_presell).size

        # Must-carry across today's planned stores (bounded set = the route).
        must = 0
        carried = 0
        planned.each do |s|
          c = s.assortment_compliance
          next unless c

          must += c[:must]
          carried += c[:carried]
        end

        # Growth: seller confirmed sellout this month vs last month (vcsi truth).
        this_m = SelloutSnapshot.mtd_actual_for(seller, month: month)
        last_m = SelloutSnapshot.mtd_actual_for(seller, month: month - 1.month)
        target = SellerTarget.find_by(seller: seller, period_type: :mtd, period_date: month)&.target_amount || 0

        # Daily goal + streak: roll up today, then compute the run of completed
        # route-days. Productive call = a visit that closed with an order today.
        productive_today = Visit.where(seller: seller, visit_date: today, status: :closed_with_order).distinct.count(:store_id)
        orders_today = Order.where(seller: seller, ordered_at: today.all_day).where.not(status: :cancelled).distinct.count(:store_id)

        # Route productivity = PLANNED stores that got an order today (visit closed
        # with an order, or an SFA order placed) / total planned stores today.
        # So visiting 1 of 8 and ordering at 1 reads 1/8 = 13%, not 100%.
        if planned_ids.any?
          ordered_planned = Order.where(seller: seller, store_id: planned_ids, ordered_at: today.all_day)
                                 .where.not(status: :cancelled).distinct.pluck(:store_id).to_set
          cwo_planned = Visit.where(seller: seller, store_id: planned_ids, visit_date: today, status: :closed_with_order)
                             .distinct.pluck(:store_id).to_set
          route_productive = (ordered_planned | cwo_planned).size
          route_pc = (route_productive * 100.0 / planned.size).round
        else
          route_pc = nil
        end
        day = SellerDailyStat.record_day!(seller, today,
                                          planned: planned.size, visited: visited_planned,
                                          productive_calls: productive_today, orders_count: orders_today)
        streak = SellerDailyStat.streak_stats(seller, today: today)

        render json: { data: {
          planned_today: planned.size, visited_today: visited_planned,
          visited_any_today: visited,                                     # incl. off-route (informational)
          # Coverage = % of the PLANNED route visited (off-route visits don't count).
          coverage_pct: planned.size.positive? ? (visited_planned * 100 / planned.size) : nil,
          pending_sync_orders: 0, # client-side metric; placeholder
          active_stores: active_stores,                                   # buying in vcsi_rise MTD
          productive_call_pct: route_pc,                                  # planned stores ordered / planned stores today
          must_carry_pct: must.positive? ? (carried * 100 / must) : nil,  # distribution width on the route
          must_carry_carried: carried, must_carry_total: must,
          last_month_amount: last_m,                                      # for the "beat last month" nudge
          growth_pct: last_m.positive? ? ((this_m - last_m) / last_m * 100).round : nil,
          attainment_pct: (target.positive? ? (this_m / target * 100).round : nil),
          # Daily goal + streak (route completion)
          streak_current: streak[:current],                               # consecutive completed route-days
          streak_best: streak[:best],
          day_goal_met: day.goal_met,
          day_goal_target: planned.size,                                  # stores due today
          day_goal_done: visited_planned                                  # planned stores visited
        }, meta: meta }
      end

      # GET /api/v1/me/priorities
      # Which of the seller's stores need attention today, ranked, with reasons
      # ("₱120k behind pace", "4 must-stock SKUs missing", "no order in 21d").
      def priorities
        today = Date.current
        due_ids = Store.joins(:route).where(routes: { seller_id: current_seller.id })
                       .select { |s| s.due_on?(today) }.map(&:id)
        rows = SellerIntelligence.new(current_seller).priorities(store_ids: due_ids).map do |r|
          s = r[:store]
          {
            store_id: s.id, name: s.name, code: s.code,
            latitude: s.latitude, longitude: s.longitude,
            score: r[:score], upside: r[:upside], reasons: r[:reasons],
          }
        end
        render json: { data: rows, meta: meta }
      end

      # GET /api/v1/me/incentives — live earnings across all schemes.
      def incentives
        render json: { data: IncentiveCalculator.new(current_seller).call, meta: meta }
      end

      # GET /api/v1/me/leaderboard?metric=target_pct|productive_call_pct|assortment|incentive
      #   &assortment_type=<code>  (optional; scopes the assortment metric to one type)
      def leaderboard
        ranking = BranchLeaderboard.new(current_seller, branch: params[:branch].presence)
                                   .ranking(params[:metric].to_s, assortment_type: params[:assortment_type].presence)
        render json: { data: ranking, meta: meta }
      end

      # GET /api/v1/me/assortment_types — enabled types for leaderboard/segment chips.
      def assortment_types
        render json: { data: AssortmentType.enabled.ordered.map { |t| { code: t.code, name: t.name } }, meta: meta }
      end

      # GET /api/v1/me/call_list?date=YYYY-MM-DD
      def call_list
        date = params[:date].present? ? Date.parse(params[:date]) : Date.current
        stores = Store.joins(:route).where(routes: { seller_id: current_seller.id })
                      .order(:visit_sequence)
        due = stores.select { |s| s.due_on?(date) }
        due_ids = due.map(&:id)

        # Off-route deviations: stores the seller visited or ordered TODAY that
        # aren't on the plan (e.g. an unplanned revisit) — surfaced here flagged
        # so the day's activity is complete on the Route tab.
        day = date.beginning_of_day..date.end_of_day
        activity_ids = (Visit.where(seller: current_seller, visit_date: date).distinct.pluck(:store_id) +
                        Order.where(seller: current_seller).where.not(status: :cancelled)
                             .where(ordered_at: day).distinct.pluck(:store_id)).uniq
        off_stores = Store.where(id: activity_ids - due_ids).order(:name).to_a
        all_ids = due_ids + off_stores.map(&:id)

        # Per-store visit status for today, for color-coding + nearest-undone:
        #   ordered   = an order was placed (or a visit closed with an order)
        #   no_order  = checked in / closed without an order
        #   none      = not visited yet
        ordered = Order.where(seller: current_seller, store_id: all_ids).where.not(status: :cancelled)
                       .where(ordered_at: day).distinct.pluck(:store_id).to_set
        visited = Visit.where(seller: current_seller, store_id: all_ids, visit_date: date).distinct.pluck(:store_id).to_set
        Visit.where(seller: current_seller, store_id: all_ids, visit_date: date, status: :closed_with_order)
             .distinct.pluck(:store_id).each { |id| ordered << id }

        row = lambda do |s, off_route|
          status = ordered.include?(s.id) ? "ordered" : visited.include?(s.id) ? "no_order" : "none"
          { store_id: s.id, name: s.name, code: s.code, visit_sequence: s.visit_sequence,
            latitude: s.latitude, longitude: s.longitude, visit_status: status, off_route: off_route }
        end
        rows = due.map { |s| row.call(s, false) } + off_stores.map { |s| row.call(s, true) }
        render json: { data: rows, meta: meta.merge(date: date) }
      end
    end
  end
end
