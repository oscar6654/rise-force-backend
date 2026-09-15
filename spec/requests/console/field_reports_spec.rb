require "rails_helper"

# Renders the two field-capture console reports (Visits + Assortment compliance)
# through the full stack — a per-seller summary (index) and a seller detail (show).
RSpec.describe "Field-capture console reports", type: :request do
  include Warden::Test::Helpers

  let(:branch) { create(:branch) }
  let(:user)   { create(:user, branch_id: nil) } # global scope
  let(:seller) { create(:seller, branch: branch) }
  let(:store)  { create(:store, branch: branch) }

  before do
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
    login_as(user, scope: :user)
  end

  def make_visit(**attrs)
    Visit.create!({ client_uuid: SecureRandom.uuid, seller: seller, store: store,
                    started_at: Time.current, visit_date: Date.current, status: :closed_with_order }.merge(attrs))
  end

  describe "visits report" do
    before do
      make_visit(off_route: true, gps_mismatch_distance_m: 320, geofence_reason: "Store relocated")
      make_visit(status: :closed_no_order, no_order_reason: "Store closed")
    end

    it "index shows a per-seller summary with tallies, not raw visit rows" do
      get visits_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Field visits")
      expect(response.body).to include(seller.name)
      expect(response.body).to include("Off route") # summary column
      # Detail-only content is not on the summary.
      expect(response.body).not_to include("Store relocated")
    end

    it "show drills into one seller's store-by-store detail" do
      get visit_path(seller)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(store.name)
      expect(response.body).to include("Store relocated") # geofence override reason
      expect(response.body).to include("Store closed")    # no-order reason
    end

    it "show filters by flag" do
      get visit_path(seller, flag: "geofence_override")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Store relocated")
    end

    it "exports CSV" do
      get download_visits_path
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("geofence_override_reason")
      expect(response.body).to include("Store relocated")
    end
  end

  describe "compliance report" do
    it "index renders the per-seller summary" do
      get compliance_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Assortment compliance")
    end

    it "show renders one seller's detail" do
      get compliance_path(seller)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("compliance")
    end

    it "exports CSV" do
      get download_compliance_index_path
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/csv")
      expect(response.body).to include("compliance_pct")
    end
  end
end
