module Api
  module V1
    class MeController < BaseController
      include DisplayApi
      include SellerPerformanceApi
      # GET /api/v1/me/targets?period=mtd
      def targets
        month = Date.current.beginning_of_month
        ids = current_group_ids # login group: sum across the seller's 2-3 records
        target = SellerTarget.where(seller_id: ids, period_type: :mtd, period_date: month).sum(:target_amount)
        actual = SelloutSnapshot.where(seller_id: ids, period_type: :mtd, period_date: month).sum(:amount)
        # "To invoice" = SFA presell this month NET of confirmed sellout (floored),
        # so it clears as vcsi confirms. See Seller#pending_presell.
        gross_presell = Order.where(seller_id: ids).where.not(status: :cancelled)
                             .where(ordered_at: month.beginning_of_day..month.end_of_month.end_of_day)
                             .sum(:total_amount)
        presell = [gross_presell - [actual, 0].max, 0].max
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
        ids = current_group_ids # login group across branches
        planned = Store.joins(:route).where(routes: { seller_id: ids }).visible_in_app.select { |s| s.due_on?(today) }
        planned_ids = planned.map(&:id)
        visited = Visit.where(seller_id: ids, visit_date: today).distinct.count(:store_id)
        # Route completion counts only PLANNED stores visited (off-route
        # deviations don't inflate the day's goal).
        visited_planned = planned_ids.any? ? Visit.where(seller_id: ids, visit_date: today, store_id: planned_ids).distinct.count(:store_id) : 0
        seller_store_ids = Store.joins(:route).where(routes: { seller_id: ids }).visible_in_app.select(:id)
        # Active stores (BLENDED): a store buying in vcsi_rise this month
        # (confirmed) OR with a presell order this month (to-invoice) — the same
        # confirmed+presell model as the sales number.
        active_vcsi = Store.active_in_vcsi(month).where(id: seller_store_ids).pluck(:id).to_set
        active_presell = Order.where(seller_id: ids, ordered_at: month..).where.not(status: :cancelled)
                              .distinct.pluck(:store_id).to_set
        active_stores = (active_vcsi | active_presell).size

        # Must-carry across today's planned stores (bounded set = the route).
        must = 0
        carried = 0
        Store.assortment_compliance_for(planned).each_value do |c|
          next unless c

          must += c[:must]
          carried += c[:carried]
        end

        # Growth: seller confirmed sellout this month vs last month (vcsi truth).
        this_m = SelloutSnapshot.where(seller_id: ids, period_type: :mtd, period_date: month).sum(:amount)
        last_m = SelloutSnapshot.where(seller_id: ids, period_type: :mtd, period_date: month - 1.month).sum(:amount)
        target = SellerTarget.where(seller_id: ids, period_type: :mtd, period_date: month).sum(:target_amount)

        # Daily goal + streak: roll up today, then compute the run of completed
        # route-days. Productive call = a visit that closed with an order today.
        productive_today = Visit.where(seller_id: ids, visit_date: today, status: :closed_with_order).distinct.count(:store_id)
        orders_today = Order.where(seller_id: ids, ordered_at: today.all_day).where.not(status: :cancelled).distinct.count(:store_id)

        # Route productivity = PLANNED stores that got an order today (visit closed
        # with an order, or an SFA order placed) / total planned stores today.
        # So visiting 1 of 8 and ordering at 1 reads 1/8 = 13%, not 100%.
        if planned_ids.any?
          ordered_planned = Order.where(seller_id: ids, store_id: planned_ids, ordered_at: today.all_day)
                                 .where.not(status: :cancelled).distinct.pluck(:store_id).to_set
          cwo_planned = Visit.where(seller_id: ids, store_id: planned_ids, visit_date: today, status: :closed_with_order)
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
          day_goal_done: visited_planned,                                 # planned stores visited
          ai_plan: (plan = AiBrief.record_for(seller, "seller_plan"))&.body, # AI game plan (nil if off)
          ai_plan_at: plan&.updated_at                                    # freshness stamp
        }, meta: meta }
      end

      # GET /api/v1/me/priorities
      # Which of the seller's stores need attention today, ranked, with reasons
      # ("₱120k behind pace", "4 must-stock SKUs missing", "no order in 21d").
      def priorities
        today = Date.current
        due_ids = Store.joins(:route).where(routes: { seller_id: current_group_ids })
                       .visible_in_app.select { |s| s.due_on?(today) }.map(&:id)
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

      # GET /api/v1/me/display_targets → this seller's stores, with executed vs
      # missing display-target lines, for the current live campaign(s).
      def display_targets
        ids = display_store_ids_for(current_group_ids)
        render json: { data: { campaigns: display_campaigns_payload(ids) }, meta: meta }
      end

      # GET /api/v1/me/display_targets/stores/:store_id → all live campaigns for it.
      def display_store
        store = Store.find(params[:store_id])
        return render_unauthorized unless display_store_ids_for(current_group_ids).include?(store.id)

        render json: { data: display_store_detail(store), meta: meta }
      end

      # GET /api/v1/me/display_targets/summary → { store_id => missing } for badges.
      def display_summary
        render json: { data: display_store_summary(display_store_ids_for(current_group_ids)), meta: meta }
      end

      # GET /api/v1/me/performance → the seller's OWN page: KPI + assortment-by-type
      # + per-store performance (the same view a manager sees when drilling into
      # this seller), scoped to the seller's login group.
      def performance
        month = Date.current.beginning_of_month
        ids = current_group_ids
        render json: { data: {
          seller: seller_kpi(current_seller, month),
          assortment: seller_assortment_by_type(ids),
          stores: store_perf(ids, month),
        }, meta: meta }
      end

      # GET /api/v1/me/stores/:id/pitch → one-line AI pitch for an own store
      # (cached daily; nil when AI is off).
      def store_pitch
        store = Store.find(params[:id])
        return render_unauthorized unless group_store_ids(current_group_ids).include?(store.id)

        text = AiBrief.current(store, "store_pitch") || Ai::Briefs.store_pitch(store)
        render json: { data: { pitch: text }, meta: meta }
      end

      # GET /api/v1/me/stores/:id/insights → per-store deep analytics for a store
      # the seller services (live from vcsi).
      def store_insights
        store = Store.find(params[:id])
        return render_unauthorized unless group_store_ids(current_group_ids).include?(store.id)

        reps = Seller.where(id: current_group_ids).where.not(vcsi_sales_rep_ref: [nil, ""])
                     .distinct.pluck(:vcsi_sales_rep_ref)
        month = self_report_month
        ttl = SystemSetting.get("manager_insights_cache_seconds", 300).to_i
        data = Rails.cache.fetch("self_store_insights/#{store.id}/#{month.strftime('%Y%m')}", expires_in: ttl.seconds) do
          ManagerInsights.new(rep_codes: reps, customer_id: store.vcsi_customer_ref, month: month).call
        end
        render json: { data: data, meta: meta }
      end

      # GET /api/v1/me/insights?month=YYYY-MM → the seller's OWN deep analytics
      # (live from vcsi): daily sales trend, top products, by category/brand — the
      # same view a manager sees for this seller, scoped to the seller's rep codes.
      def insights
        reps = Seller.where(id: current_group_ids).where.not(vcsi_sales_rep_ref: [nil, ""])
                     .distinct.pluck(:vcsi_sales_rep_ref)
        month = self_report_month
        ttl = SystemSetting.get("manager_insights_cache_seconds", 300).to_i
        data = Rails.cache.fetch("self_insights/#{current_seller.id}/#{month.strftime('%Y%m')}", expires_in: ttl.seconds) do
          d = ManagerInsights.new(rep_codes: reps, month: month).call
          d[:narrative] = Ai::Briefs.insights_narrative(d) if Ai::Anthropic.enabled?
          d
        end
        render json: { data: data, meta: meta }
      end

      # GET /api/v1/me/call_list?date=YYYY-MM-DD
      def call_list
        date = params[:date].present? ? Date.parse(params[:date]) : Date.current
        ids = current_group_ids # login group across branches
        stores = Store.joins(:route).where(routes: { seller_id: ids })
                      .visible_in_app.order(:visit_sequence)
        due = stores.select { |s| s.due_on?(date) }
        due_ids = due.map(&:id)

        # Off-route deviations: stores the seller visited or ordered TODAY that
        # aren't on the plan (e.g. an unplanned revisit) — surfaced here flagged
        # so the day's activity is complete on the Route tab.
        day = date.beginning_of_day..date.end_of_day
        activity_ids = (Visit.where(seller_id: ids, visit_date: date).distinct.pluck(:store_id) +
                        Order.where(seller_id: ids).where.not(status: :cancelled)
                             .where(ordered_at: day).distinct.pluck(:store_id)).uniq
        off_stores = Store.where(id: activity_ids - due_ids).order(:name).to_a
        all_ids = due_ids + off_stores.map(&:id)

        # Per-store visit status for today, for color-coding + nearest-undone:
        #   ordered   = an order was placed (or a visit closed with an order)
        #   no_order  = checked in / closed without an order
        #   none      = not visited yet
        ordered = Order.where(seller_id: ids, store_id: all_ids).where.not(status: :cancelled)
                       .where(ordered_at: day).distinct.pluck(:store_id).to_set
        visited = Visit.where(seller_id: ids, store_id: all_ids, visit_date: date).distinct.pluck(:store_id).to_set
        Visit.where(seller_id: ids, store_id: all_ids, visit_date: date, status: :closed_with_order)
             .distinct.pluck(:store_id).each { |id| ordered << id }

        row = lambda do |s, off_route|
          status = ordered.include?(s.id) ? "ordered" : visited.include?(s.id) ? "no_order" : "none"
          { store_id: s.id, name: s.name, code: s.code, visit_sequence: s.visit_sequence,
            latitude: s.latitude, longitude: s.longitude, visit_status: status, off_route: off_route }
        end
        rows = due.map { |s| row.call(s, false) } + off_stores.map { |s| row.call(s, true) }
        render json: { data: rows, meta: meta.merge(date: date) }
      end

      private

      # ?month=YYYY-MM (default current month) so the seller can look back.
      def self_report_month
        m = params[:month].to_s
        m.match?(/\A\d{4}-\d{2}\z/) ? Date.parse("#{m}-01") : Date.current.beginning_of_month
      rescue ArgumentError
        Date.current.beginning_of_month
      end
    end
  end
end
