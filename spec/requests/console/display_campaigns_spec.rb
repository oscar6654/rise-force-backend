require "rails_helper"

RSpec.describe "Display campaigns console", type: :request do
  include Warden::Test::Helpers
  let(:user) { create(:user, branch_id: nil) }
  let(:branch) { create(:branch) }
  let(:campaign) do
    DisplayCampaign.create!(name: "Oct", period_from: Date.current.beginning_of_month, period_to: Date.current.end_of_month)
  end

  before do
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
    login_as(user, scope: :user)
  end

  it "shows unmatched store codes and offers the downloadable list" do
    DisplayTarget.create!(display_campaign: campaign, store_code: "CU_55501", promotion_name: "P1", category: "LAUNDRY")
    get display_campaign_path(campaign)
    expect(response.body).to include("CU_55501")
    expect(response.body).to include(unmatched_display_campaign_path(campaign))

    get unmatched_display_campaign_path(campaign)
    expect(response.body).to include("unmatched_store_code")
    expect(response.body).to include("CU_55501")
  end

  it "Option B: Replace targets re-uploads a corrected xlsx, superseding + re-resolving, keeping evidence" do
    create(:store, branch: branch, store_code: "CU_90001") # the CORRECT code (in the master)
    # Campaign currently has a target with a WRONG code and some evidence.
    DisplayTarget.create!(display_campaign: campaign, store_code: "CU_WRONG", promotion_name: "OLD", category: "LAUNDRY")
    DisplayEvidence.create!(display_campaign: campaign, store_code: "CU_90001", promotion_name: "OND26_Shelving_Oct",
                            category: "LAUNDRY", brand: "ARIEL", image_url: "https://x/a.jpg", photo_taken_at: Date.current)

    file = Rack::Test::UploadedFile.new(
      Rails.root.join("spec/fixtures/files/display_targets_sample.xlsx"),
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    )
    post reimport_display_campaign_path(campaign), params: { file: file }
    expect(response).to redirect_to(display_campaign_path(campaign))

    # Old (wrong) targets are gone; the corrected file's CU_90001 rows are linked.
    expect(campaign.display_targets.where(store_code: "CU_WRONG")).to be_empty
    expect(campaign.display_targets.where(store_code: "CU_90001").where.not(store_id: nil)).to be_present
    # Evidence is untouched by a target replace.
    expect(campaign.display_evidences.count).to eq(1)
  end

  it "re-links unmatched targets + evidence after the store is added to the master" do
    DisplayTarget.create!(display_campaign: campaign, store_code: "CU_55502", promotion_name: "P1", category: "LAUNDRY")
    DisplayEvidence.create!(display_campaign: campaign, store_code: "CU_55502", promotion_name: "P1", category: "LAUNDRY",
                            image_url: "https://x/a.jpg", photo_taken_at: Date.current)
    # Store added to the master now.
    store = create(:store, branch: branch, store_code: "CU_55502")

    post relink_display_campaign_path(campaign)
    expect(response).to redirect_to(display_campaign_path(campaign))
    expect(campaign.display_targets.where(store_code: "CU_55502").first.store_id).to eq(store.id)
    expect(campaign.display_evidences.where(store_code: "CU_55502").first.store_id).to eq(store.id)
  end
end
