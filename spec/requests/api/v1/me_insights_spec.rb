require "rails_helper"

RSpec.describe "Seller self insights", type: :request do
  let(:branch) { create(:branch) }
  let(:seller) { create(:seller, branch: branch, vcsi_sales_rep_ref: "REP1") }

  def login(code, pin)
    post "/api/v1/auth/login", params: { seller_code: code, pin: pin, device_id: "d-#{code}" }, as: :json
    JSON.parse(response.body)["data"]
  end

  it "serves the seller's own performance page (KPI + assortment + stores)" do
    route = Route.create!(seller: seller, branch: branch, code: "R1", name: "R1")
    store = create(:store, branch: branch, route: route, vcsi_customer_ref: "C1", name: "Aling Nena")
    month = Date.current.beginning_of_month
    SellerTarget.create!(seller: seller, branch: branch, period_type: :mtd, period_date: month, target_amount: 100_000)
    SelloutSnapshot.create!(seller: seller, branch: branch, period_type: :mtd, period_date: month, amount: 40_000)
    StoreTarget.create!(store: store, period_type: :mtd, period_date: month, target_amount: 20_000)

    seller.update!(pin: "1234")
    token = login(seller.seller_code, "1234")["access_token"]
    get "/api/v1/me/performance", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:ok)
    d = JSON.parse(response.body)["data"]
    expect(d["seller"]["name"]).to eq(seller.name)
    expect(d["seller"]["target_amount"].to_i).to eq(100_000)
    expect(d["seller"]["confirmed_actual"].to_i).to eq(40_000)
    expect(d["assortment"]).to be_an(Array)
    expect(d["stores"].map { |s| s["name"] }).to include("Aling Nena")
  end

  it "serves the seller's own live insights (same shape the manager sees)" do
    create(:product, it_barcode: "B1", description: "Ariel 66g", case_cost: 100, pcs_per_case: 6)
    client = instance_double(VcsiRise::Client)
    allow(VcsiRise::Client).to receive(:new).and_return(client)
    allow(client).to receive(:sales_daily)
      .and_return([{ "date" => "#{Date.current.strftime('%Y-%m')}-02", "amount" => "1500.0", "pieces" => "12" }])
    allow(client).to receive(:store_sku_sellout)
      .and_return([{ "customer_id" => "C1", "it_barcode" => "B1", "amount" => "500.0", "pieces" => "5" }])
    allow(client).to receive(:store_sellout)
      .and_return([{ "customer_id" => "C1", "customer_name" => "Store C1", "sellout" => "420.0" }])

    seller.update!(pin: "1234")
    token = login(seller.seller_code, "1234")["access_token"]
    get "/api/v1/me/insights", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:ok)
    d = JSON.parse(response.body)["data"]
    expect(d["confirmed_total"]).to eq(1500.0)                 # netted daily
    expect(d["top_products"].first["description"]).to eq("Ariel 66g")
    expect(d["daily"]["this_month"].first["amount"]).to eq(1500.0)
  end
end
