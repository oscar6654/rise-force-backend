require "rails_helper"

RSpec.describe "Display targets (app views)", type: :request do
  let(:branch)  { create(:branch) }
  let(:manager) { Manager.create!(code: "MGR1", name: "Nora Manager", branch: branch) }
  let(:seller)  { create(:seller, branch: branch, name: "Seller One") }
  let!(:store)  { create(:store, branch: branch, seller: seller, store_code: "CU_90001") }
  let(:campaign) do
    DisplayCampaign.create!(name: "Oct", period_from: Date.current.beginning_of_month,
                            period_to: Date.current.end_of_month)
  end

  before do
    manager.update!(pin: "9999")
    manager.sellers << seller
    # One executed line (ARIEL) and one missing line (no evidence).
    DisplayTarget.create!(display_campaign: campaign, store: store, store_code: "CU_90001",
                          promotion_name: "P_SHELF", category: "LAUNDRY", brand: "ARIEL")
    DisplayTarget.create!(display_campaign: campaign, store: store, store_code: "CU_90001",
                          promotion_name: "P_DISP", category: "DISH CARE", brand: nil)
    DisplayEvidence.create!(display_campaign: campaign, store: store, store_code: "CU_90001",
                            promotion_name: "P_SHELF", category: "LAUNDRY", brand: "ARIEL",
                            from_date: Date.current.beginning_of_month, to_date: Date.current.end_of_month,
                            image_url: "https://x/a.jpg", photo_taken_at: Date.current)
  end

  def login(code, pin)
    post "/api/v1/auth/login", params: { seller_code: code, pin: pin, device_id: "d-#{code}" }, as: :json
    JSON.parse(response.body)["data"]
  end

  it "manager sees the team store's execution rollup" do
    token = login("MGR1", "9999")["access_token"]
    get "/api/v1/manager/display", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:ok)
    camp = JSON.parse(response.body)["data"]["campaigns"].first
    expect(camp["must"]).to eq(2)
    expect(camp["done"]).to eq(1)
    expect(camp["missing"]).to eq(1)
    row = camp["stores"].first
    expect(row["code"]).to eq("CU_90001")
    expect(row["pct"]).to eq(50)
  end

  it "manager drills into a store and sees photos + missing lines" do
    token = login("MGR1", "9999")["access_token"]
    get "/api/v1/manager/display/stores/#{store.id}", params: { campaign_id: campaign.id },
        headers: { "Authorization" => "Bearer #{token}" }
    d = JSON.parse(response.body)["data"]
    expect(d["done"]).to eq(1)
    shelf = d["lines"].find { |l| l["promotion_name"] == "P_SHELF" }
    expect(shelf["executed"]).to be(true)
    expect(shelf["photos"].first["image_url"]).to eq("https://x/a.jpg")
    disp = d["lines"].find { |l| l["promotion_name"] == "P_DISP" }
    expect(disp["executed"]).to be(false)
    expect(disp["photos"]).to be_empty
  end

  it "the seller sees their own store's targets" do
    seller.update!(pin: "1234")
    token = login(seller.seller_code, "1234")["access_token"]
    get "/api/v1/me/display_targets", headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:ok)
    camp = JSON.parse(response.body)["data"]["campaigns"].first
    expect(camp["stores"].first["store_id"]).to eq(store.id)
    expect(camp["missing"]).to eq(1)
  end

  it "a manager cannot drill into a store outside the team" do
    other = create(:store, branch: branch, store_code: "CU_99999")
    token = login("MGR1", "9999")["access_token"]
    get "/api/v1/manager/display/stores/#{other.id}", params: { campaign_id: campaign.id },
        headers: { "Authorization" => "Bearer #{token}" }
    expect(response).to have_http_status(:unauthorized)
  end
end
