require "rails_helper"

RSpec.describe IncentiveCalculator do
  let(:branch) { create(:branch) }
  let(:seller) { create(:seller, branch: branch, vcsi_sales_rep_ref: "R1") }
  let(:month) { Date.current.beginning_of_month }

  it "pays the highest achieved target tier plus base, on confirmed sales" do
    SellerTarget.create!(seller: seller, period_type: :mtd, period_date: month, target_amount: 100_000)
    SelloutSnapshot.create!(seller: seller, store_id: nil, product_id: nil, branch: branch,
                            period_type: :mtd, period_date: month, amount: 105_000)
    IncentiveScheme.create!(name: "T", scheme_type: :target_multiplier, status: :active,
                            config: { base_payout: 500, tiers: [{ pct: 100, payout: 2000 }, { pct: 120, payout: 2000, multiplier: 1.5 }] })

    r = described_class.new(seller).call
    expect(r[:confirmed_total]).to eq(2500) # 2000 (100 tier) + 500 base
  end

  it "pays focus-SKU per piece from vcsi_rise confirmed pieces" do
    product = create(:product, it_barcode: "BC1")
    SkuSelloutSnapshot.create!(seller: seller, product: product, it_barcode: "BC1", period_date: month, pieces: 240)
    IncentiveScheme.create!(name: "F", scheme_type: :focus_sku, status: :active,
                            config: { product_ids: [product.id], rate_per_piece: 0.5 })

    r = described_class.new(seller).call
    expect(r[:confirmed_total]).to eq(120) # 240 * 0.5
  end

  it "respects branch scoping (a scheme for another branch doesn't apply)" do
    other = create(:branch)
    IncentiveScheme.create!(name: "X", scheme_type: :coverage, status: :active, branch: other,
                            config: { metric: "active_stores", threshold: 0, payout: 999 })
    expect(described_class.new(seller).call[:schemes]).to be_empty
  end
end

RSpec.describe "Seller PIN" do
  it "authenticates against a per-seller PIN when set, else needs the shared PIN" do
    seller = create(:seller)
    expect(seller.pin_set?).to be(false)
    seller.update!(pin: "2468")
    expect(seller.pin_set?).to be(true)
    expect(seller.authenticate_pin("2468")).to be_truthy
    expect(seller.authenticate_pin("0000")).to be_falsey
  end
end
