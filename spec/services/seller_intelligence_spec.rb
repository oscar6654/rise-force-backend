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

  it "recommends what the NEAREST stores carry, regardless of channel" do
    mini_mart = Channel.create!(code: "MR", name: "Mini-mart", status: :active)
    # A small neighbour on a DIFFERENT channel, right next door.
    peer = create(:store, branch: branch, channel: mini_mart, category_code: "silver",
                          latitude: 14.6005, longitude: 120.9805)
    coffee = create(:product, it_barcode: "1111")
    milk   = create(:product, it_barcode: "2222")
    order_for(store, coffee) # this store already carries coffee
    order_for(peer, coffee)
    order_for(peer, milk)    # neighbour also carries milk -> whitespace = milk

    recs = described_class.new(seller).nearby_whitespace(store)
    ids = recs.map { |r| r[:product_id] }
    expect(ids).to include(milk.id)
    expect(ids).not_to include(coffee.id)
    expect(recs.find { |r| r[:product_id] == milk.id }[:peer_stores]).to eq(1)
  end

  it "counts confirmed vcsi sellout as carried at nearby stores" do
    peer = create(:store, branch: branch, channel: channel, category_code: "gold",
                          latitude: 14.6002, longitude: 120.9802)
    juice = create(:product, it_barcode: "3333")
    StoreSkuSellout.create!(store: peer, it_barcode: "3333", pieces: 12, amount: 500,
                            period_date: Date.current.beginning_of_month)

    ids = described_class.new(seller).nearby_whitespace(store).map { |r| r[:product_id] }
    expect(ids).to include(juice.id)
  end

  it "builds a smart-start order from recent baskets" do
    coffee = create(:product)
    order_for(store, coffee, qty: 4, days_ago: 3)
    sug = described_class.new(seller).suggested_order(store)
    expect(sug.first[:product_id]).to eq(coffee.id)
    expect(sug.first[:suggested_qty]).to eq(4)
  end
end
