require "rails_helper"

RSpec.describe "Manager app views", type: :request do
  let(:branch)  { create(:branch) }
  let(:manager) { Manager.create!(code: "MGR1", name: "Nora Manager", branch: branch) }
  let(:s1) { create(:seller, branch: branch, name: "Seller One") }
  let(:s2) { create(:seller, branch: branch, name: "Seller Two") }
  let(:store1) { create(:store, branch: branch, seller: s1, vcsi_customer_ref: "C1") }
  let(:month)  { Date.current.beginning_of_month }

  before do
    manager.update!(pin: "9999")
    manager.sellers << [s1, s2] # tag the sellers to this manager (many-to-many)
  end

  def login(code, pin)
    post "/api/v1/auth/login", params: { seller_code: code, pin: pin, device_id: "m-#{code}" }, as: :json
    JSON.parse(response.body)["data"]
  end

  it "logs a manager in and returns the manager role" do
    d = login("MGR1", "9999")
    expect(response).to have_http_status(:ok)
    expect(d["role"]).to eq("manager")
    expect(d["manager"]["name"]).to eq("Nora Manager")
  end

  it "returns a combined team scoreboard across the manager's sellers" do
    s1; s2
    SellerTarget.create!(seller: s1, branch: branch, period_type: :mtd, period_date: month, target_amount: 100_000)
    SellerTarget.create!(seller: s2, branch: branch, period_type: :mtd, period_date: month, target_amount: 50_000)
    SelloutSnapshot.create!(seller: s1, branch: branch, period_type: :mtd, period_date: month, amount: 40_000)

    token = login("MGR1", "9999")["access_token"]
    get "/api/v1/manager/team", headers: { "Authorization" => "Bearer #{token}" }
    d = JSON.parse(response.body)["data"]
    expect(d["totals"]["target_amount"].to_i).to eq(150_000)
    expect(d["totals"]["confirmed_actual"].to_i).to eq(40_000)
    expect(d["sellers"].map { |r| r["name"] }).to include("Seller One", "Seller Two")
  end

  it "drills into one seller's store performance" do
    store1
    token = login("MGR1", "9999")["access_token"]
    get "/api/v1/manager/sellers/#{s1.id}", headers: { "Authorization" => "Bearer #{token}" }
    d = JSON.parse(response.body)["data"]
    expect(d["seller"]["name"]).to eq("Seller One")
    expect(d["stores"].map { |s| s["store_id"] }).to include(store1.id)
  end

  it "lets a seller sit under multiple managers" do
    other = Manager.create!(code: "MGR2", name: "Branch Boss")
    other.sellers << s1
    expect(s1.reload.managers.map(&:code)).to contain_exactly("MGR1", "MGR2")
    expect(other.sellers).to include(s1)
    expect(manager.sellers).to include(s1) # still under the first too
  end

  it "includes per-type assortment on the seller view + a store-detail endpoint" do
    store1
    token = login("MGR1", "9999")["access_token"]
    hdr = { "Authorization" => "Bearer #{token}" }

    get "/api/v1/manager/sellers/#{s1.id}", headers: hdr
    expect(JSON.parse(response.body)["data"]).to have_key("assortment")

    get "/api/v1/manager/stores/#{store1.id}", headers: hdr
    sd = JSON.parse(response.body)["data"]
    expect(sd["store"]["store_id"]).to eq(store1.id)
    expect(sd["store"]).to have_key("attainment_pct")
    expect(sd).to have_key("assortment")

    # a store outside the manager's team is forbidden
    outside = create(:store, branch: create(:branch))
    get "/api/v1/manager/stores/#{outside.id}", headers: hdr
    expect(response).to have_http_status(:unauthorized)
  end

  it "serves live deep insights (daily trend + top products + category)" do
    s1.update!(vcsi_sales_rep_ref: "REP1")
    create(:product, it_barcode: "B1", description: "Ariel 66g", case_cost: 100)
    client = instance_double(VcsiRise::Client)
    allow(VcsiRise::Client).to receive(:new).and_return(client)
    allow(client).to receive(:sales_daily)
      .and_return([{ "date" => "#{Date.current.strftime('%Y-%m')}-02", "amount" => "1500.0", "pieces" => "12" }])
    allow(client).to receive(:store_sku_sellout)
      .and_return([{ "customer_id" => "C1", "it_barcode" => "B1", "amount" => "500.0", "pieces" => "5" }])

    token = login("MGR1", "9999")["access_token"]
    get "/api/v1/manager/insights", headers: { "Authorization" => "Bearer #{token}" }
    d = JSON.parse(response.body)["data"]
    expect(d["daily"]["this_month"].first["amount"]).to eq(1500.0)
    expect(d["top_products"].first["description"]).to eq("Ariel 66g")
    expect(d["by_category"]).to be_an(Array)
    # Headline total nets returns via the daily feed (matches the ERP), not the
    # per-SKU rows which drop negative-net barcodes.
    expect(d["confirmed_total"]).to eq(1500.0)

    # Month-picker: ?month=YYYY-MM looks back at a prior month.
    get "/api/v1/manager/insights", params: { month: "2026-07" }, headers: { "Authorization" => "Bearer #{token}" }
    expect(JSON.parse(response.body)["data"]["period"]).to eq("2026-07")
  end

  it "cannot see a seller outside the manager's team" do
    other = create(:seller, branch: branch)
    token = login("MGR1", "9999")["access_token"]
    get "/api/v1/manager/sellers/#{other.id}", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:not_found)
  end
end
