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

  it "persists a delivery_date when provided" do
    post "/api/v1/orders", headers: auth_header, as: :json, params: {
      client_uuid: "dd-1", store_id: store.id, delivery_date: "2026-10-25",
      lines: [{ product_id: product.id, quantity: 1, uom: "case" }],
    }
    expect(response).to have_http_status(:created)
    expect(Order.find_by(client_uuid: "dd-1").delivery_date).to eq(Date.new(2026, 10, 25))
  end

  it "rejects an order with no delivery_date when the seller's section requires one" do
    seller.update!(section: "North")
    SystemSetting.set("delivery_date_sections", "North")
    post "/api/v1/orders", headers: auth_header, as: :json, params: {
      client_uuid: "dd-req", store_id: store.id,
      lines: [{ product_id: product.id, quantity: 1, uom: "case" }],
    }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "code")).to eq("delivery_date_required")
    expect(Order.find_by(client_uuid: "dd-req")).to be_nil
  end

  it "persists remarks (stored as notes)" do
    post "/api/v1/orders", headers: auth_header, as: :json, params: {
      client_uuid: "rmk-1", store_id: store.id, notes: "Deliver AM only",
      lines: [{ product_id: product.id, quantity: 1, uom: "case" }],
    }
    expect(response).to have_http_status(:created)
    expect(Order.find_by(client_uuid: "rmk-1").notes).to eq("Deliver AM only")
  end

  it "Seller#delivery_date_required? is gated by section + SystemSetting" do
    seller.update!(section: "North")
    expect(seller.delivery_date_required?).to be(false)        # setting blank
    SystemSetting.set("delivery_date_sections", "North, East")
    expect(seller.reload.delivery_date_required?).to be(true)  # section listed
    seller.update!(section: "South")
    expect(seller.delivery_date_required?).to be(false)        # not listed
  end
end
