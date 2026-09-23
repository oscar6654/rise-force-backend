require "rails_helper"

RSpec.describe "PromoEngine combo_percent" do
  let(:branch) { create(:branch) }
  let(:store)  { create(:store, branch: branch) }
  # ₱100/case, 12 pc/case (matches the tiered spec's pricing fallback).
  let(:a) { create(:product, pcs_per_case: 12, case_cost: 100, item_cost: 10, it_barcode: "A1") }
  let(:b) { create(:product, pcs_per_case: 12, case_cost: 100, item_cost: 10, it_barcode: "B1") }

  before do
    p = Promo.create!(code: "COMBO", name: "Buy A24 + B12 → 10%", mechanic_type: :combo_percent,
                      status: :active, start_date: Date.current - 1, end_date: Date.current + 1,
                      config: { "rate" => 0.10 })
    p.promo_lines.create!(role: :qualifying, it_barcode: "A1", product: a, min_qty: 24) # pieces
    p.promo_lines.create!(role: :qualifying, it_barcode: "B1", product: b, min_qty: 12)
  end

  it "applies 10% ex-VAT off the qualifying items when EVERY minimum is met" do
    r = PromoEngine.new(store).preview([
      { product_id: a.id, quantity: 2, uom: "case" }, # 24 pc, ₱200
      { product_id: b.id, quantity: 1, uom: "case" },  # 12 pc, ₱100
    ])
    # (200 + 100)/1.12 × 10% = 26.79
    expect(r[:promo_savings].to_f).to eq(26.79)
    expect(r[:promo_breakdown].first[:kind]).to eq("combo_percent")
  end

  it "gives no discount but nudges the shortfall when one item is short" do
    r = PromoEngine.new(store).preview([{ product_id: a.id, quantity: 2, uom: "case" }]) # A met, B missing
    expect(r[:promo_savings].to_f).to eq(0.0)
    expect(r[:nudges].first[:text]).to include("12 pc")
    expect(r[:nudges].first[:text]).to include("10% off")
  end

  it "is silent (no nudge) before the seller adds any of the combo's items" do
    other = create(:product, it_barcode: "Z9")
    r = PromoEngine.new(store).preview([{ product_id: other.id, quantity: 1, uom: "case" }])
    expect(r[:nudges]).to be_empty
  end
end
