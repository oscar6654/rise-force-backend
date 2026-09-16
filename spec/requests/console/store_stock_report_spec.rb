require "rails_helper"

# The store show page's stock-check & replenishment panel + its CSV report,
# through the full stack.
RSpec.describe "Store stock-check console panel", type: :request do
  include Warden::Test::Helpers

  let(:branch) { create(:branch) }
  let(:user)   { create(:user, branch_id: nil) }
  let(:seller) { create(:seller, branch: branch) }
  let(:store)  { create(:store, branch: branch, seller: seller, visit_frequency: :f2, visit_day: nil) }
  let(:coffee) { create(:product, it_barcode: "C1", pcs_per_case: 12) }

  before do
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
    login_as(user, scope: :user)
    v0 = Visit.create!(seller: seller, store: store, client_uuid: SecureRandom.uuid,
                       visit_date: 15.days.ago.to_date, status: :closed_no_order, no_order_reason: "count")
    v1 = Visit.create!(seller: seller, store: store, client_uuid: SecureRandom.uuid,
                       visit_date: 5.days.ago.to_date, status: :closed_no_order, no_order_reason: "count")
    StockCount.create!(visit: v0, product: coffee, client_uuid: SecureRandom.uuid, qty: 100)
    StockCount.create!(visit: v1, product: coffee, client_uuid: SecureRandom.uuid, qty: 40)
  end

  it "shows the replenishment panel with a suggested order on the store page" do
    get store_path(store)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Stock check &amp; replenishment")
    expect(response.body).to include(coffee.sku)
    expect(response.body).to include("Count history")
  end

  it "downloads the compiled stock report CSV" do
    get stock_report_store_path(store, format: :csv)
    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include("text/csv")
    expect(response.body).to include("Suggested cases")
    expect(response.body).to include(coffee.sku)
    expect(response.body).to include("offtake")
  end

  it "downloads the raw count-history CSV filtered by counted date" do
    # Full range includes both counts (100 and 40 pieces).
    get stock_history_store_path(store, format: :csv)
    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include("text/csv")
    expect(response.body).to include("Pieces on shelf")
    expect(response.body).to include("100")
    expect(response.body).to include("40")

    # Narrow to the last week → only the 40-piece count (5 days ago) remains.
    get stock_history_store_path(store, format: :csv, from: 7.days.ago.to_date.iso8601)
    expect(response.body).to include("40")
    expect(response.body).not_to include(",100,")
  end

  it "date-filters the count history shown on the store page" do
    get store_path(store, from: 7.days.ago.to_date.iso8601)
    expect(response).to have_http_status(:ok)
    # Only the 5-days-ago count date should be listed, not the 15-days-ago one.
    expect(response.body).to include(5.days.ago.to_date.strftime("%b %-d"))
    expect(response.body).not_to include(15.days.ago.to_date.strftime("%b %-d, %Y"))
  end
end
