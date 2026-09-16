require "rails_helper"

RSpec.describe "Replenishment console report", type: :request do
  include Warden::Test::Helpers

  let(:branch) { create(:branch) }
  let(:user)   { create(:user, branch_id: nil) }
  let(:seller) { create(:seller, branch: branch) }
  let(:store)  { create(:store, branch: branch, seller: seller, visit_frequency: :f2, visit_day: nil, name: "Aling Nena") }
  let(:coffee) { create(:product, it_barcode: "C1", pcs_per_case: 12) }

  before do
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
    login_as(user, scope: :user)
    v0 = Visit.create!(seller: seller, store: store, client_uuid: SecureRandom.uuid, visit_date: 15.days.ago.to_date, status: :closed_no_order, no_order_reason: "c")
    v1 = Visit.create!(seller: seller, store: store, client_uuid: SecureRandom.uuid, visit_date: 5.days.ago.to_date, status: :closed_no_order, no_order_reason: "c")
    StockCount.create!(visit: v0, product: coffee, client_uuid: SecureRandom.uuid, qty: 100)
    StockCount.create!(visit: v1, product: coffee, client_uuid: SecureRandom.uuid, qty: 40)
    store.update_column(:last_stock_checked_at, 5.days.ago)
  end

  it "lists stock-checked stores with a suggested case order and store search" do
    get replenishment_index_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Stock &amp; replenishment")
    expect(response.body).to include("Aling Nena")
    expect(response.body).to include("Suggested cases")

    get replenishment_index_path(q: "Nena")
    expect(response.body).to include("Aling Nena")
  end

  it "exports the fleet CSV" do
    get replenishment_index_path(format: :csv)
    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include("text/csv")
    expect(response.body).to include("Total suggested cases")
    expect(response.body).to include("Aling Nena")
  end
end
