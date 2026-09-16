require "rails_helper"

RSpec.describe StoreInventoryEstimator do
  let(:branch) { create(:branch) }
  let(:seller) { create(:seller, branch: branch) }
  let(:store) do
    create(:store, branch: branch, seller: seller, visit_frequency: :f2, visit_day: nil,
                   vcsi_customer_ref: "C-INV")
  end
  let(:coffee) { create(:product, it_barcode: "C1", pcs_per_case: 12) }

  def count!(pieces, days_ago:)
    v = Visit.create!(seller: seller, store: store, client_uuid: SecureRandom.uuid,
                      visit_date: days_ago.days.ago.to_date, status: :closed_no_order, no_order_reason: "count")
    StockCount.create!(visit: v, product: coffee, client_uuid: SecureRandom.uuid, qty: pieces)
  end

  it "infers offtake between two counts and sizes the ICO to cover days" do
    count!(100, days_ago: 15) # t0
    count!(40, days_ago: 5)   # t1 (freshest)

    row = described_class.new(store).rows.find { |r| r.product_id == coffee.id }
    expect(row).to be_present
    # counts are 10 days apart (15d ago → 5d ago): offtake = (100 - 40)/10 = 6/day
    expect(row.offtake_per_day).to eq(6.0)
    # predicted now = 40 - 6 * 5 days since last count = 10
    expect(row.predicted_on_hand).to eq(10)
    # cover = 14 (F2 default cycle, no visit day) + 3 safety = 17
    # ICO = 6*17 - 10 = 92 pieces => 8 cases (12/case)
    expect(row.cover_days).to eq(17)
    expect(row.suggested_pieces).to eq(92)
    expect(row.suggested_cases).to eq(8)
    expect(row.basis).to eq("offtake")
  end

  it "counts vcsi confirmed deliveries as stock added between counts" do
    count!(100, days_ago: 40)
    count!(90, days_ago: 10)
    # A confirmed delivery this period means real offtake is higher than the raw
    # 10-piece drop (they sold what was delivered too).
    StoreSkuSellout.create!(store: store, it_barcode: "C1", pieces: 60, amount: 500,
                            period_date: Date.current.beginning_of_month)

    row = described_class.new(store).rows.find { |r| r.product_id == coffee.id }
    expect(row.offtake_per_day).to be > 0.3 # (100 + delivered - 90)/30 >> raw 10/30
  end

  it "falls back to a delivery proxy when there is only one count" do
    count!(50, days_ago: 3)
    StoreSkuSellout.create!(store: store, it_barcode: "C1", pieces: 90, amount: 500,
                            period_date: Date.current.beginning_of_month)
    row = described_class.new(store).rows.find { |r| r.product_id == coffee.id }
    expect(row.basis).to eq("delivery")     # 90/30 = 3/day proxy
    expect(row.offtake_per_day).to eq(3.0)
  end

  it "returns nothing for a store never stock-checked" do
    expect(described_class.new(store).rows).to eq([])
  end
end
