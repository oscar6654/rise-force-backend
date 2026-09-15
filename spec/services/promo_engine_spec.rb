require "rails_helper"

RSpec.describe PromoEngine do
  it "qualifies buy_x_get_y by PIECES — a full case or loose pieces both count" do
    branch = create(:branch)
    store = create(:store, branch: branch)
    product = create(:product, pcs_per_case: 12)
    promo = Promo.create!(code: "PBX", name: "Buy 60 get 1", mechanic_type: :buy_x_get_y,
                          status: :active, start_date: Date.current - 1, end_date: Date.current + 1)
    promo.promo_lines.create!(role: :qualifying, product: product, min_qty: 60) # pieces
    promo.promo_lines.create!(role: :reward, product: product, reward_qty: 1)

    eng = PromoEngine.new(store)
    expect(eng.preview([{ product_id: product.id, quantity: 5, uom: "case" }])[:earned_lines].size).to eq(1) # 5×12 = 60 pc
    expect(eng.preview([{ product_id: product.id, quantity: 60, uom: "pc" }])[:earned_lines].size).to eq(1)  # 60 pc loose
    expect(eng.preview([{ product_id: product.id, quantity: 3, uom: "case" }])[:earned_lines].size).to eq(0) # 36 pc < 60

    nudge = eng.preview([{ product_id: product.id, quantity: 4, uom: "case" }])[:nudges] # 48 pc, 12 short
    expect(nudge.first[:text]).to include("12 more pc")
  end

  describe "tiered_discount (FMCG volume deals)" do
    let(:branch) { create(:branch) }
    let(:store)  { create(:store, branch: branch) }
    # case_cost 100, 12 pc/case → each case = ₱100 and 12 pieces.
    let(:product) { create(:product, pcs_per_case: 12, case_cost: 100, item_cost: 10) }

    it "picks the right PIECE tier: 4% for 18-71 pc, 7% for 72+ pc" do
      promo = Promo.create!(code: "TIER-PC", name: "Volume 4/7%", mechanic_type: :tiered_discount,
                            status: :active, start_date: Date.current - 1, end_date: Date.current + 1,
                            config: { "basis" => "pieces", "tiers" => [{ "min" => 18, "rate" => 0.04 }, { "min" => 72, "rate" => 0.07 }] })
      promo.promo_lines.create!(role: :qualifying, product: product)
      eng = PromoEngine.new(store)

      # Discounts are EX-VAT: 4% of (₱200 / 1.12) = 7.14; 7% of (₱600 / 1.12) = 37.50.
      expect(eng.preview([{ product_id: product.id, quantity: 1, uom: "case" }])[:promo_savings].to_f).to eq(0.0)   # 12 pc < 18
      expect(eng.preview([{ product_id: product.id, quantity: 2, uom: "case" }])[:promo_savings].to_f).to eq(7.14)  # 24 pc → 4% ex-VAT
      expect(eng.preview([{ product_id: product.id, quantity: 6, uom: "case" }])[:promo_savings].to_f).to eq(37.5)  # 72 pc → 7% ex-VAT
    end

    it "nudges toward the next piece tier" do
      promo = Promo.create!(code: "TIER-PC2", name: "Volume", mechanic_type: :tiered_discount,
                            status: :active, start_date: Date.current - 1, end_date: Date.current + 1,
                            config: { "basis" => "pieces", "tiers" => [{ "min" => 18, "rate" => 0.04 }, { "min" => 72, "rate" => 0.07 }] })
      promo.promo_lines.create!(role: :qualifying, product: product)
      nudges = PromoEngine.new(store).preview([{ product_id: product.id, quantity: 2, uom: "case" }])[:nudges] # 24 pc
      expect(nudges.first[:text]).to include("48 pc").and include("7% off") # 72-24
    end

    it "applies bundle_price: any 3 pcs for a fixed ₱ (saving vs normal)" do
      promo = Promo.create!(code: "BUN", name: "3 for 100", mechanic_type: :bundle_price,
                            status: :active, start_date: Date.current - 1, end_date: Date.current + 1)
      # case_cost 100 / 12 pc ≈ ₱8.33/pc → 3 pc normal ≈ ₱25; bundle price ₱20 → saves ₱5/bundle.
      promo.promo_lines.create!(role: :qualifying, product: product, min_qty: 3, fixed_price: 20)
      # 6 pc = 2 bundles → ~₱10 off.
      d = PromoEngine.new(store).preview([{ product_id: product.id, quantity: 6, uom: "pc" }])[:promo_savings].to_f
      expect(d).to be > 0
    end

    it "applies a spend threshold: ₱100 off ≥₱1200, ₱300 off ≥₱3000 (whole order)" do
      promo = Promo.create!(code: "SPEND", name: "Spend & save", mechanic_type: :tiered_discount,
                            status: :active, start_date: Date.current - 1, end_date: Date.current + 1,
                            config: { "basis" => "amount", "tiers" => [{ "min" => 1200, "amount" => 100 }, { "min" => 3000, "amount" => 300 }] })
      eng = PromoEngine.new(store) # no qualifying lines → whole order

      # Thresholds compare the EX-VAT basket: ₱1000/1.12=₱893 < 1200; ₱2000/1.12=₱1786 ≥ 1200; ₱3500/1.12=₱3125 ≥ 3000.
      expect(eng.preview([{ product_id: product.id, quantity: 10, uom: "case" }])[:promo_savings].to_f).to eq(0.0)   # ex-VAT ₱893 < 1200
      expect(eng.preview([{ product_id: product.id, quantity: 20, uom: "case" }])[:promo_savings].to_f).to eq(100.0) # ex-VAT ₱1786
      expect(eng.preview([{ product_id: product.id, quantity: 35, uom: "case" }])[:promo_savings].to_f).to eq(300.0) # ex-VAT ₱3125
    end
  end
end
