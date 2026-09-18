require "rails_helper"

# One physical rep covering 2 branches (2 vcsi rep codes = 2 seller records)
# signs in ONCE and sees both, combined. No merge.
RSpec.describe "Login group (one login across 2 branches)", type: :request do
  let(:b1) { create(:branch) }
  let(:b2) { create(:branch) }
  let(:primary)   { create(:seller, branch: b1, seller_code: "A1", vcsi_sales_rep_ref: "REPA") }
  let(:secondary) { create(:seller, branch: b2, seller_code: "A2", vcsi_sales_rep_ref: "REPB", primary_seller: primary) }
  let(:store_a) { create(:store, branch: b1, seller: primary,   vcsi_customer_ref: "CA") }
  let(:store_b) { create(:store, branch: b2, seller: secondary, vcsi_customer_ref: "CB") }
  let(:product) { create(:product) }
  let(:month)   { Date.current.beginning_of_month }

  def token(seller)
    jti = SecureRandom.uuid
    DeviceToken.create!(seller: seller, jti: jti, device_id: "d-#{seller.id}", role: "seller")
    { "Authorization" => "Bearer #{JsonWebToken.encode({ seller_id: seller.id, jti: jti, role: 'seller' })}" }
  end

  before { store_a; store_b }

  it "sees BOTH branches' stores from one login" do
    get "/api/v1/sync/stores", headers: token(primary)
    ids = JSON.parse(response.body)["data"].map { |s| s["id"] }
    expect(ids).to include(store_a.id, store_b.id)
  end

  it "resolves the group logging in as EITHER member" do
    get "/api/v1/sync/stores", headers: token(secondary)
    ids = JSON.parse(response.body)["data"].map { |s| s["id"] }
    expect(ids).to include(store_a.id, store_b.id)
  end

  it "sums targets + confirmed across the group" do
    SellerTarget.create!(seller: primary,   branch: b1, period_type: :mtd, period_date: month, target_amount: 100_000)
    SellerTarget.create!(seller: secondary, branch: b2, period_type: :mtd, period_date: month, target_amount: 50_000)
    SelloutSnapshot.create!(seller: primary,   branch: b1, period_type: :mtd, period_date: month, amount: 30_000)
    SelloutSnapshot.create!(seller: secondary, branch: b2, period_type: :mtd, period_date: month, amount: 20_000)

    get "/api/v1/me/targets", headers: token(primary)
    d = JSON.parse(response.body)["data"]
    expect(d["target_amount"].to_i).to eq(150_000)
    expect(d["actual_amount"].to_i).to eq(50_000)
  end

  it "attributes an order at branch-2's store to the OWNING seller (for OSB/vcsi)" do
    post "/api/v1/orders", params: {
      client_uuid: SecureRandom.uuid, store_id: store_b.id, ordered_at: Time.current.iso8601,
      lines: [{ product_id: product.id, quantity: 2, uom: "case" }]
    }, headers: token(primary), as: :json
    expect(response).to have_http_status(:created)
    expect(Order.last.seller_id).to eq(secondary.id)
    expect(Order.last.branch_id).to eq(b2.id)
  end
end
