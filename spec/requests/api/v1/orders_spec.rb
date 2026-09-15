require "rails_helper"

RSpec.describe "Api::V1::Orders", type: :request do
  let(:branch) { create(:branch) }
  let(:seller) { create(:seller, branch: branch) }
  let(:store)  { create(:store, branch: branch, category_code: "gold") }
  let(:product) { create(:product, tier_code: "mainstream", item_cost: 100, case_cost: 100) }

  before do
    gold = StoreCategory.find_or_create_by_code("gold")
    mainstream = ProductTier.find_or_create_by_code("mainstream")
    version = create(:pricing_version)
    version.pricing_rules.create!(store_category: gold, product_tier: mainstream, markup_rate: 0.15)
    version.publish!(nil)
    store; product # ensure the same masters are used
  end

  def auth_header
    jti = SecureRandom.uuid
    DeviceToken.create!(seller: seller, jti: jti, device_id: "d1")
    { "Authorization" => "Bearer #{JsonWebToken.encode({ seller_id: seller.id, jti: jti })}" }
  end

  it "rejects requests without a valid token" do
    post "/api/v1/orders", params: { client_uuid: "x", store_id: store.id }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it "creates an order and snapshots server-resolved prices" do
    body = { client_uuid: "uuid-1", store_id: store.id,
             lines: [{ product_id: product.id, quantity: 5, uom: "case_uom" }] }
    post "/api/v1/orders", params: body, headers: auth_header, as: :json

    expect(response).to have_http_status(:created)
    data = response.parsed_body["data"]
    expect(data["order_number"]).to be_present
    expect(data["total_amount"].to_f).to eq(575.0) # 5 * (100 * 1.15)
    expect(Order.count).to eq(1)
  end

  it "is idempotent on client_uuid (replay returns the same order)" do
    body = { client_uuid: "uuid-dupe", store_id: store.id,
             lines: [{ product_id: product.id, quantity: 1, uom: "case_uom" }] }
    headers = auth_header

    post "/api/v1/orders", params: body, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    first_number = response.parsed_body.dig("data", "order_number")

    post "/api/v1/orders", params: body, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "order_number")).to eq(first_number)
    expect(Order.count).to eq(1)
  end
end
