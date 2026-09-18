require "rails_helper"

RSpec.describe "Diser login + visitless stock counts", type: :request do
  let(:branch)  { create(:branch) }
  let(:seller)  { create(:seller, branch: branch, seller_code: "SLR9", diser_code: "DSR9", diser_name: "Boy Diser") }
  let(:store)   { create(:store, branch: branch, seller: seller) }
  let(:product) { create(:product) }

  before { seller.update!(diser_pin: "4321") }

  def login(code, pin)
    post "/api/v1/auth/login", params: { seller_code: code, pin: pin, device_id: "dv-#{code}" }, as: :json
    JSON.parse(response.body)["data"]
  end

  it "logs a diser in with the diser code + PIN, returning the diser role" do
    data = login("DSR9", "4321")
    expect(response).to have_http_status(:ok)
    expect(data["role"]).to eq("diser")
    expect(data["seller"]["name"]).to eq("Boy Diser")
    expect(data["access_token"]).to be_present
  end

  it "rejects a wrong diser PIN" do
    login("DSR9", "0000")
    expect(response).to have_http_status(:unauthorized)
  end

  it "submits a store-scoped count with NO visit (no coverage impact)" do
    token = login("DSR9", "4321")["access_token"]
    expect do
      post "/api/v1/stock_counts",
           params: { store_id: store.id, counted_on: Date.current.iso8601,
                     counts: [{ client_uuid: "d-1", product_id: product.id, qty: 7 }] },
           headers: { "Authorization" => "Bearer #{token}" }, as: :json
    end.to change(StockCount, :count).by(1)
    expect(response).to have_http_status(:created)
    expect(Visit.count).to eq(0) # never touches coverage

    sc = StockCount.last
    expect(sc.store_id).to eq(store.id)
    expect(sc.visit_id).to be_nil
    expect(sc.counted_on).to eq(Date.current)
    expect(store.reload.last_stock_checked_at).to be_present
  end

  it "feeds the store's inventory engine and reads back the last count" do
    token = login("DSR9", "4321")["access_token"]
    post "/api/v1/stock_counts",
         params: { store_id: store.id, counts: [{ client_uuid: "d-2", product_id: product.id, qty: 5 }] },
         headers: { "Authorization" => "Bearer #{token}" }, as: :json

    get "/api/v1/stores/#{store.id}/last_stock_counts", headers: { "Authorization" => "Bearer #{token}" }
    expect(JSON.parse(response.body)["data"]).to eq([{ "product_id" => product.id, "qty" => "5.0" }])
    # And the estimator sees the diser count (store-scoped grain).
    expect(StoreInventoryEstimator.new(store).rows.map(&:product_id)).to include(product.id)
  end

  it "cannot count a store outside the seller's coverage" do
    other = create(:store, branch: create(:branch))
    token = login("DSR9", "4321")["access_token"]
    post "/api/v1/stock_counts",
         params: { store_id: other.id, counts: [{ client_uuid: "x", product_id: product.id, qty: 1 }] },
         headers: { "Authorization" => "Bearer #{token}" }, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
