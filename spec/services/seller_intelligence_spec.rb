require "rails_helper"

RSpec.describe SellerIntelligence do
  let(:branch) { create(:branch) }
  let(:channel) { Channel.create!(code: "SS", name: "Sari-Sari", status: :active) }
  let(:seller) { create(:seller, branch: branch, vcsi_sales_rep_ref: "R1") }
  let(:store) do
    create(:store, branch: branch, channel: channel, category_code: "gold", seller: seller,
                   vcsi_customer_ref: "C-M", latitude: 14.60, longitude: 120.98)
  end
  let(:month) { Date.current.beginning_of_month }

  def order_for(s, product, qty: 3, days_ago: 5)
    o = create(:order, store: s, seller: seller, branch: branch, ordered_at: days_ago.days.ago)
    o.order_lines.create!(product: product, quantity: qty, uom: "case_uom", line_total: qty * 100)
    o
  end

  it "flags a behind-pace store with reasons and peso upside" do
    StoreTarget.create!(store: store, period_type: :monthly, period_date: month,
                        target_amount: 100_000, basis_amount: 90_000, months_used: 3, growth_rate: 0.05)
    SelloutSnapshot.create!(store: store, seller_id: nil, product_id: nil, branch: branch,
                            period_type: :mtd, period_date: month, amount: 5_000)

    rows = described_class.new(seller).priorities
    mine = rows.find { |r| r[:store].id == store.id }
    expect(mine).to be_present
    expect(mine[:upside]).to be > 0
    expect(mine[:reasons].map { |r| r[:code] }).to include("behind_pace")
  end

  it "recommends SKUs nearby peers buy that this store doesn't" do
    peer = create(:store, branch: branch, channel: channel, category_code: "gold",
                          latitude: 14.601, longitude: 120.981)
    coffee = create(:product)
    milk = create(:product)
    order_for(store, coffee)          # mine already buys coffee
    order_for(peer, coffee)
    order_for(peer, milk)             # peer also buys milk -> recommend milk

    recs = described_class.new(seller).cross_sell(store)
    ids = recs.map { |r| r[:product_id] }
    expect(ids).to include(milk.id)
    expect(ids).not_to include(coffee.id)
  end

  it "builds a smart-start order from recent baskets" do
    coffee = create(:product)
    order_for(store, coffee, qty: 4, days_ago: 3)
    sug = described_class.new(seller).suggested_order(store)
    expect(sug.first[:product_id]).to eq(coffee.id)
    expect(sug.first[:suggested_qty]).to eq(4)
  end
end
