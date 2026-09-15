require "rails_helper"

RSpec.describe "Api::V1 seller-scoped sync", type: :request do
  let(:branch) { create(:branch) }
  let(:seller) { create(:seller, branch: branch, vcsi_sales_rep_ref: "REP-9") }
  let(:route)  { Route.create!(seller: seller, branch: branch, code: "R1", name: "R1") }
  let!(:store) { create(:store, branch: branch, route: route, vcsi_customer_ref: "SC-1") }
  let(:month)  { Date.current.beginning_of_month }

  def auth_header
    jti = SecureRandom.uuid
    DeviceToken.create!(seller: seller, jti: jti, device_id: "d1")
    { "Authorization" => "Bearer #{JsonWebToken.encode({ seller_id: seller.id, jti: jti })}" }
  end

  def stub_client
    client = instance_double(VcsiRise::Client)
    allow(VcsiRise::Client).to receive(:new).and_return(client)
    allow(client).to receive(:sellout).with(hash_including(sales_rep: "REP-9"))
      .and_return([{ "sales_rep" => "REP-9", "sellout" => "250000.0", "transactions" => 7 }])
    allow(client).to receive(:store_sellout).with(hash_including(sales_rep: "REP-9"))
      .and_return([{ "customer_id" => "SC-1", "sellout" => "40000.0", "transactions" => 3 }])
    allow(client).to receive(:store_sku_sellout).with(hash_including(sales_rep: "REP-9"))
      .and_return([{ "customer_id" => "SC-1", "it_barcode" => "4800000001", "pieces" => "12.0", "amount" => "1450.0" }])
    allow(client).to receive(:sellers).with(hash_including(sales_rep: "REP-9"))
      .and_return([{ "sales_rep" => "REP-9", "sales_target" => "500000.0" }])
    client
  end

  describe "POST /api/v1/sync/refresh" do
    it "pulls the seller's own vcsi_rise data and upserts snapshots" do
      stub_client
      post "/api/v1/sync/refresh", headers: auth_header, as: :json

      expect(response).to have_http_status(:ok)
      body = response.parsed_body["data"]
      expect(body["refreshed"]).to be(true)
      expect(body["stores_updated"]).to eq(1)
      # headline target vs actual returned in the same round-trip
      expect(body["summary"]["target_amount"].to_f).to eq(500_000)
      expect(body["summary"]["confirmed_actual"].to_f).to eq(250_000)
      expect(body["summary"]["attainment_pct"]).to eq(50)
      expect(seller.reload.actual_for(month)).to eq(250_000)
      expect(store.confirmed_actual(month)).to eq(40_000)
      expect(store.active_in_vcsi?(month)).to be(true)
    end

    it "throttles a second immediate pull" do
      stub_client
      header = auth_header
      post "/api/v1/sync/refresh", headers: header, as: :json
      post "/api/v1/sync/refresh", headers: header, as: :json
      expect(response.parsed_body["data"]["throttled"]).to be(true)
    end
  end

  describe "GET /api/v1/sync/store_performance" do
    it "returns per-store achievement for the seller's stores after a pull" do
      stub_client
      post "/api/v1/sync/refresh", headers: auth_header, as: :json

      get "/api/v1/sync/store_performance", headers: auth_header, as: :json
      expect(response).to have_http_status(:ok)
      row = response.parsed_body["data"].find { |r| r["store_id"] == store.id }
      expect(row["confirmed_actual"].to_f).to eq(40_000)
      expect(row["active"]).to be(true)
    end

    it "delta: excludes stores whose vcsi data predates updated_since" do
      stub_client
      post "/api/v1/sync/refresh", headers: auth_header, as: :json

      get "/api/v1/sync/store_performance", params: { updated_since: 1.minute.from_now.iso8601 },
          headers: auth_header, as: :json
      expect(response.parsed_body["data"]).to be_empty
    end
  end
end
