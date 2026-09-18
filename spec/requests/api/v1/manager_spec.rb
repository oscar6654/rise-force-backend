require "rails_helper"

RSpec.describe "Manager app views", type: :request do
  let(:branch)  { create(:branch) }
  let(:manager) { Manager.create!(code: "MGR1", name: "Nora Manager", branch: branch) }
  let(:s1) { create(:seller, branch: branch, name: "Seller One", manager: manager) }
  let(:s2) { create(:seller, branch: branch, name: "Seller Two", manager: manager) }
  let(:store1) { create(:store, branch: branch, seller: s1, vcsi_customer_ref: "C1") }
  let(:month)  { Date.current.beginning_of_month }

  before { manager.update!(pin: "9999") }

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

  it "cannot see a seller outside the manager's team" do
    other = create(:seller, branch: branch)
    token = login("MGR1", "9999")["access_token"]
    get "/api/v1/manager/sellers/#{other.id}", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:not_found)
  end
end
