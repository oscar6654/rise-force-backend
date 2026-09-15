module Import
  # Bulk-loads promos keyed by `code` (upsert), scoped to SKUs by `it_barcode`
  # (a barcode → every item_key that shares it) so real-world FMCG promo sheets
  # (100+ rows) don't have to be entered by hand. CSV headers:
  #   code, name, mechanic, basis, it_barcode, tiers, min_qty, reward_qty,
  #   reward_barcode, channel_code, category, branch_code, start_date, end_date,
  #   per_store_limit, status
  # `tiers` is a compact list "min:value|min:value" — value is a rate for a
  # percent tier (0.04 = 4%) or a peso amount for a spend tier (100).
  #   tiered_discount + basis pieces:  "18:0.04|72:0.07"  (4% 18–71 pc, 7% 72+)
  #   tiered_discount + basis amount:  "1200:100|3000:300" (₱100 ≥1200, ₱300 ≥3000)
  #   buy_x_get_y:                     min_qty (pieces) + reward_qty [+ reward_barcode]
  class PromosImporter < BaseImporter
    JOB_TYPE = :promo_import
    MECHANICS = %w[tiered_discount buy_x_get_y free_goods bundle_price discount_percent discount_amount].freeze

    private

    def import_row(row)
      code = row["code"].to_s.strip
      raise "code is required" if code.blank?

      mechanic = (row["mechanic"] || row["mechanic_type"]).to_s.strip
      raise "mechanic must be one of #{MECHANICS.join(', ')}" unless MECHANICS.include?(mechanic)

      barcode = row["it_barcode"].to_s.strip
      raise "unknown it_barcode '#{barcode}' — not in product master" if barcode.present? && !Product.exists?(it_barcode: barcode)

      promo = Promo.find_or_initialize_by(code: code)
      promo.assign_attributes(
        name: row["name"].presence || promo.name || code,
        mechanic_type: mechanic,
        status: (row["status"].presence || "active"),
        start_date: parse_date(row["start_date"]),
        end_date: parse_date(row["end_date"]),
        per_store_limit: row["per_store_limit"].presence,
        config: build_config(mechanic, row)
      )
      promo.save!
      rebuild_lines(promo, mechanic, barcode, row)
      rebuild_eligibility(promo, row)
    end

    def build_config(mechanic, row)
      return {} unless mechanic == "tiered_discount"

      basis = row["basis"].to_s.strip.presence || "pieces"
      raise "basis must be 'pieces' or 'amount'" unless %w[pieces amount].include?(basis)

      tiers = Promo.parse_tiers(row["tiers"], basis)
      raise "tiered_discount needs tiers, e.g. \"18:0.04|72:0.07\"" if tiers.empty?

      { "basis" => basis, "tiers" => tiers }
    end

    def rebuild_lines(promo, mechanic, barcode, row)
      promo.promo_lines.destroy_all
      first_pid = ->(bc) { Product.where(it_barcode: bc).limit(1).pick(:id) }

      case mechanic
      when "tiered_discount", "discount_percent", "discount_amount"
        # A qualifying SKU scopes the deal; blank = whole-order (spend basis).
        return if barcode.blank?

        promo.promo_lines.create!(role: :qualifying, it_barcode: barcode, product_id: first_pid.call(barcode),
                                  discount_rate: row["discount_rate"].presence, discount_amount: row["discount_amount"].presence)
      when "buy_x_get_y", "free_goods"
        raise "#{mechanic} needs it_barcode + min_qty + reward_qty" if barcode.blank? || row["min_qty"].blank?

        promo.promo_lines.create!(role: :qualifying, it_barcode: barcode, product_id: first_pid.call(barcode), min_qty: row["min_qty"])
        reward_bc = row["reward_barcode"].presence || barcode
        raise "unknown reward_barcode '#{reward_bc}'" unless Product.exists?(it_barcode: reward_bc)

        promo.promo_lines.create!(role: :reward, it_barcode: reward_bc, product_id: first_pid.call(reward_bc), reward_qty: (row["reward_qty"].presence || 1))
      when "bundle_price"
        raise "bundle_price needs it_barcode + min_qty + fixed_price" if barcode.blank? || row["min_qty"].blank? || row["fixed_price"].blank?

        promo.promo_lines.create!(role: :qualifying, it_barcode: barcode, product_id: first_pid.call(barcode),
                                  min_qty: row["min_qty"], fixed_price: row["fixed_price"])
      end
    end

    def rebuild_eligibility(promo, row)
      # channel_code may list several channels — separate them with a SEMICOLON
      # in the one CSV cell (commas would split the column), e.g.
      # "HFS WHOLESALE SS - Gold;HFS WHOLESALE OTC - Gold". Each becomes its own
      # eligibility row and a store matches if ANY row matches; category/branch
      # (if set) apply to each. (Pipe/comma are also tolerated for pasted values.)
      channels = row["channel_code"].to_s.split(/[,;|]/).map { |c| lookup!(Channel, c, "channel_code") }.compact
      category = lookup!(StoreCategory, row["category"], "category")
      branch   = lookup!(Branch, row["branch_code"], "branch_code")
      promo.promo_eligibilities.destroy_all

      if channels.any?
        channels.each { |ch| promo.promo_eligibilities.create!(channel: ch, store_category_ref: category, branch: branch) }
      elsif category || branch
        promo.promo_eligibilities.create!(store_category_ref: category, branch: branch)
      end
    end

    def lookup!(model, code, label)
      return nil if code.to_s.strip.blank?

      rec = model.find_by("LOWER(code) = ?", code.to_s.strip.downcase)
      raise "unknown #{label} '#{code}'" if rec.nil?

      rec
    end

    def parse_date(str)
      str.present? ? Date.parse(str.to_s) : nil
    rescue ArgumentError
      nil
    end
  end
end
