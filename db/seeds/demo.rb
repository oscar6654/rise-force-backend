# Rich demo data for end-to-end app testing, built around seller SLR-DEMO.
# Run: bin/rails runner db/seeds/demo.rb
# Idempotent-ish (find_or_create by code). Demo stores are intentionally NOT
# linked to vcsi_rise (blank vcsi_customer_ref) so the seller-scoped sync never
# overwrites the seeded store sellout / targets.
require "securerandom"

seller = Seller.find_by!(seller_code: "SLR-DEMO")
seller.update!(pin: "1234") unless seller.pin_set?
branch = seller.branch
month = Date.current.beginning_of_month
today = Date.current
visit_day = %i[sun mon tue wed thu fri sat][today.wday] # today's weekday -> due today
visit_day = :sat if visit_day == :sun # routes run Mon–Sat; on a Sunday demo, use Saturday
puts "Seeding for #{seller.name} (#{seller.seller_code}); PIN=1234; stores due today = #{visit_day}"

# ---- Masters: channels, tiers, categories, pricing --------------------------
channel = Channel.find_or_create_by!(code: "SARI") { |c| c.name = "Sari-Sari"; c.status = :active }
Channel.find_or_create_by!(code: "GROC") { |c| c.name = "Grocery"; c.status = :active }
tiers = %w[premium mainstream value].to_h { |t| [t, ProductTier.find_or_create_by_code(t)] }
cats  = %w[platinum gold silver bronze].to_h { |c| [c, StoreCategory.find_or_create_by_code(c)] }

pv = PricingVersion.where(status: :published).order(:effective_date).last ||
     PricingVersion.create!(name: "Demo v1", effective_date: Date.current)
cats.each_value do |cat|
  tiers.each_value do |tier|
    next if pv.pricing_rules.exists?(store_category: cat, product_tier: tier)

    markup = { "platinum" => 0.10, "gold" => 0.15, "silver" => 0.20, "bronze" => 0.25 }[cat.code]
    pv.pricing_rules.create!(store_category: cat, product_tier: tier, markup_rate: markup)
  end
end
pv.publish!(nil) unless pv.published?

# ---- Products ---------------------------------------------------------------
PRODUCTS = [
  ["Kopiko Brown 3in1 10s", "Kopiko", "mainstream", 8,   96,  "4800016641107"],
  ["Bear Brand Powder 33g", "Bear Brand", "premium", 12, 288, "4800361380011"],
  ["Lucky Me Pancit Canton", "Lucky Me", "value", 7,   84,  "4807770271014"],
  ["Nescafe Original 3in1", "Nescafe", "mainstream", 9, 108, "4800361381018"],
  ["Milo Powder 24g", "Milo", "premium", 11, 264, "4800361280015"],
  ["Argentina Corned Beef", "Argentina", "mainstream", 25, 300, "4800194120012"],
  ["Datu Puti Vinegar 385ml", "Datu Puti", "value", 15, 180, "4800016023019"],
  ["Piattos Cheese 40g", "Piattos", "mainstream", 10, 120, "4800016333019"],
  ["Palmolive Shampoo 12ml", "Palmolive", "value", 5, 144, "4800888140012"],
  ["Safeguard Soap 55g", "Safeguard", "premium", 18, 216, "4902430735018"],
  ["Tang Orange 25g", "Tang", "value", 6, 72, "4800361290014"],
  ["Great Taste White 3in1", "Great Taste", "mainstream", 8, 96, "4800016641207"],
].map do |desc, brand_name, tier, item_cost, case_cost, barcode|
  brand = Brand.find_or_create_by_name(brand_name)
  Product.find_or_create_by!(sku: "SKU-#{barcode[-5..]}") do |p|
    p.description = desc
    p.brand = brand
    p.tier_code = tier
    p.item_cost = item_cost
    p.case_cost = case_cost
    p.it_barcode = barcode
    p.pcs_per_case = 12
    p.status = :active
  end
end
puts "Products: #{PRODUCTS.size}"

# ---- Route + stores (due today) ---------------------------------------------
route = Route.find_or_create_by!(seller: seller, code: "QC-DEMO") { |r| r.branch = branch; r.name = "QC Demo Route"; r.status = :active }
STORE_DEFS = [
  ["Aling Nena Store", "gold",   14.6760, 121.0437],
  ["Mang Tomas Sari-Sari", "silver", 14.6510, 121.0490],
  ["JM Mini Mart", "gold", 14.6600, 121.0350],
  ["Tindahan ni Aling Rosa", "bronze", 14.6685, 121.0521],
  ["7-Steps Convenience", "platinum", 14.6420, 121.0388],
  ["Kuya Ben Store", "silver", 14.6805, 121.0300],
  ["Lola Ising Sari-Sari", "bronze", 14.6555, 121.0600],
  ["Sunrise Grocery", "gold", 14.6710, 121.0250],
].each_with_index.map do |(name, cat, lat, lng), i|
  store = Store.find_or_initialize_by(store_code: "DEMO-S#{i + 1}")
  store.assign_attributes(
    branch: branch, channel: channel, route: route, name: name,
    owner_name: name.split.first, address: "Quezon City", latitude: lat, longitude: lng,
    category_code: cat, status: :active,
    visit_frequency: :f4, week_pattern: :every_week, visit_day: visit_day, visit_sequence: i + 1,
    # Fake vcsi ref: counts as "linked" for the intelligence engine but never
    # matches a real vcsi_rise customer_id, so sync never overwrites seeded data.
    vcsi_customer_ref: "DEMO-C#{i + 1}"
  )
  store.save!
  store
end
puts "Stores on route (due today): #{STORE_DEFS.size}"

# ---- Assortments (must-carry) with types ------------------------------------
focus_type = AssortmentType.find_or_create_by!(code: "focus") { |t| t.name = "Focus"; t.position = 2 }
dist_type  = AssortmentType.find_or_create_by!(code: "distribution") { |t| t.name = "Distribution"; t.position = 0 }
focus = Assortment.find_or_create_by!(name: "Focus Coffee Line") { |a| a.channel = channel; a.status = :active; a.assortment_type = focus_type }
dist  = Assortment.find_or_create_by!(name: "Core Distribution") { |a| a.channel = channel; a.status = :active; a.assortment_type = dist_type }
focus.assortment_items.destroy_all
PRODUCTS.select { |p| p.description =~ /Coffee|Kopiko|Nescafe|Great Taste|Milo/ }.each { |p| focus.assortment_items.create!(product: p, must_stock: true) }
dist.assortment_items.destroy_all
PRODUCTS.first(8).each { |p| dist.assortment_items.create!(product: p, must_stock: true) }

# ---- Promo (buy X get Y -> triggers the order nudge) ------------------------
promo = Promo.find_or_create_by!(code: "DEMO-BXGY") do |pr|
  pr.name = "Buy 60 pcs Kopiko (5 cases), get 1 free"
  pr.mechanic_type = :buy_x_get_y
  pr.status = :active
  pr.start_date = month
  pr.end_date = month.end_of_month
  pr.per_store_limit = 2
end
kopiko = PRODUCTS.find { |p| p.description.include?("Kopiko") }
promo.promo_lines.destroy_all
# min_qty is in PIECES: 5 cases × 12 pcs = 60 pc (so 5 cases OR 60 pcs qualifies).
promo.promo_lines.create!(role: :qualifying, product: kopiko, it_barcode: kopiko.it_barcode, min_qty: 60)
promo.promo_lines.create!(role: :reward, product: kopiko, it_barcode: kopiko.it_barcode, reward_qty: 1)

# ---- Tiered volume discount (real FMCG mechanic): 4% off 18-71 pcs, 7% off 72+ ---
tiered = Promo.find_or_create_by!(code: "DEMO-TIER") do |pr|
  pr.name = "Kopiko volume: 4% off 18–71 pcs, 7% off 72+"
  pr.mechanic_type = :tiered_discount
  pr.status = :active
  pr.start_date = month
  pr.end_date = month.end_of_month
  pr.config = { "basis" => "pieces", "tiers" => [{ "min" => 18, "rate" => 0.04 }, { "min" => 72, "rate" => 0.07 }] }
end
tiered.promo_lines.destroy_all
tiered.promo_lines.create!(role: :qualifying, product: kopiko, it_barcode: kopiko.it_barcode)

# ---- Spend threshold (real FMCG mechanic): ₱100 off ≥₱1200, ₱300 off ≥₱3000 -----
spend = Promo.find_or_create_by!(code: "DEMO-SPEND") do |pr|
  pr.name = "Spend & save: ₱100 off ₱1,200 · ₱300 off ₱3,000"
  pr.mechanic_type = :tiered_discount
  pr.status = :active
  pr.start_date = month
  pr.end_date = month.end_of_month
  pr.config = { "basis" => "amount", "tiers" => [{ "min" => 1200, "amount" => 100 }, { "min" => 3000, "amount" => 300 }] }
end
spend.promo_lines.destroy_all # no qualifying lines → whole-order spend

# A few more real-world variants (single threshold + steeper tier), by barcode.
# On DISTINCT products so they don't stack (the engine sums all applicable promos).
piattos = PRODUCTS.find { |p| p.description.include?("Piattos") }
other   = PRODUCTS.reject { |p| p.description =~ /Kopiko|Piattos/ }.first
[
  ["DEMO-VOL144", "#{piattos&.description}: 4% off 144 pcs or more", piattos, { "basis" => "pieces", "tiers" => [{ "min" => 144, "rate" => 0.04 }] }],
  ["DEMO-VOL714", "#{other&.description}: 7% off 16–31 pcs, 14% off 32+", other, { "basis" => "pieces", "tiers" => [{ "min" => 16, "rate" => 0.07 }, { "min" => 32, "rate" => 0.14 }] }],
].each do |code, name, product, cfg|
  next unless product

  pr = Promo.find_or_create_by!(code: code) do |p|
    p.name = name; p.mechanic_type = :tiered_discount; p.status = :active
    p.start_date = month; p.end_date = month.end_of_month; p.config = cfg
  end
  pr.update!(config: cfg, name: name)
  pr.promo_lines.destroy_all
  pr.promo_lines.create!(role: :qualifying, product: product, it_barcode: product.it_barcode)
end
puts "Promos: #{Promo.count} (#{Promo.where(mechanic_type: :tiered_discount).count} tiered volume deals)"

# ---- Orders (recent, varied) -> history, suggested, cross-sell, predictive ---
STORE_DEFS.each_with_index do |store, si|
  3.times do |n|
    days_ago = (n * 12) + si # spread cadence
    o = Order.find_or_create_by!(client_uuid: "demo-#{store.id}-#{n}") do |ord|
      ord.seller = seller; ord.store = store; ord.branch = branch; ord.route = route
      ord.ordered_at = days_ago.days.ago; ord.status = :submitted
    end
    next if o.order_lines.any?

    PRODUCTS.sample(4 + si % 3).each do |p|
      o.order_lines.create!(product: p, quantity: [1, 2, 3].sample, uom: "case_uom",
                            base_price: p.case_cost, unit_price: (p.case_cost * 1.15).round(2),
                            line_total: (p.case_cost * 1.15 * 2).round(2))
    end
    o.recompute_total!
  end
end

# ---- Store sellout snapshots + derived targets (seeded; unlinked from vcsi) --
STORE_DEFS.each_with_index do |store, i|
  actual = [40_000, 80_000, 120_000, 15_000, 200_000, 60_000, 9_000, 95_000][i]
  SelloutSnapshot.find_or_initialize_by(store: store, seller_id: nil, product_id: nil, period_type: :mtd, period_date: month).tap do |s|
    s.assign_attributes(branch: branch, amount: actual, quantity: 5 + i, synced_at: Time.current); s.save!
  end
  basis = actual * 1.05
  StoreTarget.find_or_initialize_by(store: store, period_type: :monthly, period_date: month).tap do |t|
    t.assign_attributes(branch: branch, target_amount: (basis * 1.1).round(2), basis_amount: basis.round(2), months_used: 3, growth_rate: 0.1, synced_at: Time.current); t.save!
  end
end

# ---- Visits (productive-call %) ---------------------------------------------
STORE_DEFS.first(6).each_with_index do |store, i|
  st = i < 4 ? :closed_with_order : :closed_no_order
  Visit.find_or_create_by!(client_uuid: "demo-visit-#{store.id}") do |v|
    v.seller = seller; v.store = store; v.route = route
    v.visit_date = (i).days.ago.to_date; v.status = st
    v.no_order_reason = ("store closed" if st == :closed_no_order)
  end
end

# ---- Seller target + confirmed (only if not vcsi-driven) --------------------
SellerTarget.find_or_initialize_by(seller: seller, period_type: :mtd, period_date: month).tap do |t|
  t.assign_attributes(branch: branch, target_amount: 1_500_000, synced_at: Time.current); t.save!
end

# ---- Incentive schemes (all four types) -------------------------------------
IncentiveScheme.find_or_create_by!(name: "Monthly Target Bonus") do |s|
  s.scheme_type = :target_multiplier; s.status = :active
  s.config = { "base_payout" => 1000, "tiers" => [{ "pct" => 80, "payout" => 2000 }, { "pct" => 100, "payout" => 4000 }, { "pct" => 120, "payout" => 4000, "multiplier" => 1.5 }] }
end
kopiko = PRODUCTS.find { |p| p.description.include?("Kopiko") }
IncentiveScheme.find_or_create_by!(name: "Push Kopiko (per piece)") do |s|
  s.scheme_type = :focus_sku; s.status = :active
  # Keyed by it_barcode: any item_key/SKU sharing this barcode counts.
  s.config = { "it_barcodes" => [kopiko.it_barcode], "rate_per_piece" => 0.50 }
end
IncentiveScheme.find_or_create_by!(name: "Distribution Bonus (Focus)") do |s|
  s.scheme_type = :assortment_completion; s.status = :active
  s.config = { "assortment_type" => "focus", "payout_per_store" => 100 }
end
IncentiveScheme.find_or_create_by!(name: "Coverage Bonus") do |s|
  s.scheme_type = :coverage; s.status = :active
  s.config = { "metric" => "productive_call_pct", "threshold" => 70, "payout" => 1500 }
end

# ---- Focus-SKU confirmed pieces (so incentive shows confirmed earnings) ------
SkuSelloutSnapshot.find_or_initialize_by(seller: seller, product: kopiko, period_date: month).tap do |s|
  s.assign_attributes(it_barcode: kopiko.it_barcode, pieces: 320, amount: 3072, synced_at: Time.current); s.save!
end

puts "DONE. Log in to the app as SLR-DEMO / 1234 (or the persisted session). #{STORE_DEFS.size} stores due today, #{Order.where(seller: seller).count} orders, #{IncentiveScheme.count} incentive schemes."
