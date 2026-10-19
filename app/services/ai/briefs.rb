# frozen_string_literal: true

module Ai
  # Builds the AI assist text from the data the app already computes, calls
  # Claude, and upserts an AiBrief. Each method returns the text (or nil). Cheap
  # by design: tiny prompts, short outputs, precomputed once/day.
  class Briefs
    def self.money(amount)
      "₱#{amount.to_i}"
    end

    # ① Seller "Today's game plan" — 3 action bullets for the route.
    def self.seller_plan(seller)
      client = Ai::Anthropic.new
      return nil unless client.available?

      month = Date.current.beginning_of_month
      h = seller.headline(month)
      pri = SellerIntelligence.new(seller, month: month).priorities(limit: 5)
      stores = pri.map { |r| "- #{r[:store].name}: #{r[:reasons].map { |x| x[:text] }.join('; ')}" }.join("\n")
      data = <<~TXT
        Seller: #{seller.name}
        Attainment: #{h[:attainment_pct] || '—'}% (target #{money(h[:target_amount])}, actual #{money(h[:blended_actual])})
        To invoice (orders not yet confirmed): #{money(h[:presell_pending])}
        Productive calls MTD: #{seller.route_productive_call_pct(month) || '—'}%
        Priority stores today:
        #{stores.presence || '- none flagged'}
      TXT
      body = client.complete(
        system: "You are a sharp, encouraging FMCG field-sales coach. Write a van seller's daily game plan they read on their phone before their route. Reference the named stores and the numbers. Exactly 3 short bullets starting with '•', action-first, max 55 words total. No preamble, no sign-off.",
        prompt: data, max_tokens: 300,
      )
      AiBrief.store(seller, "seller_plan", body, model: client.model, on: Date.current) if body.present?
      body
    end

    # ④ Manager daily digest — 3 things to act on across the team.
    def self.manager_digest(manager)
      client = Ai::Anthropic.new
      return nil unless client.available?

      month = Date.current.beginning_of_month
      rows = manager.sellers.active.where(primary_seller_id: nil).includes(:branch).map do |s|
        h = s.headline(month)
        { name: s.name, branch: s.branch&.name, section: s.section,
          pct: h[:attainment_pct], to_invoice: h[:presell_pending].to_i }
      end
      return nil if rows.empty?

      ranked = rows.sort_by { |r| r[:pct] || -1 }
      lines = ranked.map { |r| "- #{r[:name]} (#{[r[:branch], r[:section]].compact.join('/')}): #{r[:pct] || '—'}% attainment, #{money(r[:to_invoice])} to invoice" }.join("\n")
      data = <<~TXT
        Manager: #{manager.name}
        Team (#{rows.size} sellers), lowest attainment first:
        #{lines}
      TXT
      body = client.complete(
        system: "You are a field-sales manager's morning assistant. From the team data, write a 3-point action digest: name the 1-2 sellers/sections that most need attention today and why (low attainment, big to-invoice), plus one positive callout. Each point one short line starting with '•'. Max 60 words. No preamble.",
        prompt: data, max_tokens: 320,
      )
      AiBrief.store(manager, "manager_digest", body, model: client.model, on: Date.current) if body.present?
      body
    end

    # Weekly manager roundup — a Monday "how we're tracking + focus this week".
    # Stored under the week's Monday so one row per manager per week.
    def self.manager_weekly(manager)
      client = Ai::Anthropic.new
      return nil unless client.available?

      month = Date.current.beginning_of_month
      rows = manager.sellers.active.where(primary_seller_id: nil).includes(:branch).map do |s|
        h = s.headline(month)
        { name: s.name, section: s.section, pct: h[:attainment_pct] }
      end
      return nil if rows.empty?

      lines = rows.sort_by { |r| r[:pct] || -1 }.map { |r| "- #{r[:name]} (#{r[:section] || '—'}): #{r[:pct] || '—'}%" }.join("\n")
      body = client.complete(
        system: "You are a sales manager's weekly coach. Write a Monday roundup: how the team is tracking this month, the 1-2 sellers/sections to focus on this week, and one concrete goal. 3-4 short bullets starting with '•'. Max 70 words. No preamble.",
        prompt: "Manager: #{manager.name}\nTeam attainment this month (lowest first):\n#{lines}",
        max_tokens: 350,
      )
      AiBrief.store(manager, "manager_weekly", body, model: client.model, on: Date.current.beginning_of_week) if body.present?
      body
    end

    # ⑤ Insight narration — 2 sentences on what stands out in a sellout dataset.
    # Not persisted (callers cache it with the insights payload). `data` is the
    # ManagerInsights hash.
    def self.insights_narrative(data)
      client = Ai::Anthropic.new
      return nil unless client.available?

      top   = Array(data[:top_products]).first(5).map { |p| "#{p[:description]} #{money(p[:amount])}" }.join(", ")
      cats  = Array(data[:by_category]).first(5).map { |c| "#{c[:name]} #{c[:share]}%" }.join(", ")
      stores = Array(data[:by_store]).first(5).map { |s| "#{s[:name]} #{money(s[:amount])}" }.join(", ")
      last_m = Array(data.dig(:daily, :last_month)).sum { |d| d[:amount].to_f }
      prompt = <<~TXT
        Period: #{data[:period]}
        Confirmed sellout: #{money(data[:confirmed_total])} (last month same span: #{money(last_m)})
        Top products: #{top.presence || 'n/a'}
        By category share: #{cats.presence || 'n/a'}
        Top stores: #{stores.presence || 'n/a'}
      TXT
      client.complete(
        system: "You are a sales analyst. In 2 short sentences (max 40 words), call out what stands out: a notable mover, a category concentration, or a change vs last month. Specific, no fluff, no preamble.",
        prompt: prompt, max_tokens: 150,
      )
    end

    # ② Per-store pitch — one punchy line: what to sell here and why. Cached daily.
    def self.store_pitch(store)
      client = Ai::Anthropic.new
      return nil unless client.available?

      comp = store.assortment_compliance
      gaps = comp ? Product.where(id: comp[:gap_product_ids]).limit(6).pluck(:description).compact : []
      last = Order.where(store: store).where.not(status: :cancelled).maximum(:ordered_at)
      prompt = <<~TXT
        Store: #{store.name} (#{store.category_letter})
        Missing must-stock SKUs: #{gaps.join(', ').presence || 'none'}
        Last order: #{last ? "#{(Date.current - last.to_date).to_i} days ago" : 'never'}
      TXT
      body = client.complete(
        system: "You are an FMCG sales rep's assistant. In ONE punchy line (max 25 words), tell the rep what to pitch at this store and why. Lead with the action; name SKUs if given.",
        prompt: prompt, max_tokens: 100,
      )
      AiBrief.store(store, "store_pitch", body, model: client.model, on: Date.current) if body.present?
      body
    end

    # ③ Order sanity nudge — one line when the basket is well below the usual.
    def self.order_nudge(store:, total:, usual:)
      client = Ai::Anthropic.new
      return nil unless client.available?

      client.complete(
        system: "You are a sales assistant. The current order is well below this store's usual size. In ONE short line (max 20 words), nudge the rep to double-check they didn't miss items — friendly and specific, not pushy.",
        prompt: "Store: #{store.name}\nThis order: #{money(total)}\nUsual order: #{money(usual)}",
        max_tokens: 80,
      )
    end
  end
end
