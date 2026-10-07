require "rails_helper"

RSpec.describe "Display importers" do
  let(:branch) { create(:branch) }
  let!(:alpha) { create(:store, branch: branch, store_code: "CU_90001") }
  let(:campaign) do
    DisplayCampaign.create!(name: "OCT", period_from: Date.new(2026, 10, 1), period_to: Date.new(2026, 10, 31))
  end

  describe Import::DisplayTargetsImporter do
    it "parses the xlsx base file, extracting the CU code and resolving the store" do
      path = Rails.root.join("spec/fixtures/files/display_targets_sample.xlsx").to_s
      log = described_class.new(path, campaign: campaign, user: nil, filename: "t.xlsx").call

      expect(log.status).to eq("completed")
      expect(log.processed_rows).to eq(3) # trailing empty row skipped
      expect(campaign.display_targets.count).to eq(3)

      alpha_lines = campaign.display_targets.where(store_code: "CU_90001")
      expect(alpha_lines.pluck(:store_id).uniq).to eq([alpha.id])
      expect(alpha_lines.where(brand: nil).count).to eq(1) # blank-brand row kept as nil
      expect(campaign.display_targets.find_by(store_code: "CU_90002").store_id).to be_nil # not in master
    end

    it "supersedes the campaign's targets on re-run" do
      path = Rails.root.join("spec/fixtures/files/display_targets_sample.xlsx").to_s
      described_class.new(path, campaign: campaign, user: nil, filename: "t.xlsx").call
      described_class.new(path, campaign: campaign, user: nil, filename: "t.xlsx").call
      expect(campaign.display_targets.count).to eq(3) # not doubled
    end
  end

  describe Import::DisplayEvidenceImporter do
    let(:csv) do
      <<~CSV
        Customer Name,Store Code,Store ID,Store Channel,Store Name,Visit Date,Siebel Id,Promotion Name,Promotion Description,From,To,Product Category: Product Hierarchy Name,Product Hierarchy: Product Hierarchy Name,Image URL,Created Date,Activity Type
        VCSI,3000001,40599,CVS,CU_90001 - ALPHA MART,10/3/2026,PH1,OND26_Shelving_Oct,desc,10/1/2026,10/31/2026,LAUNDRY,ARIEL,https://x/a.jpg,10/5/2026,Visibility
        VCSI,3000001,40599,CVS,CU_90001 - ALPHA MART,10/3/2026,PH2,OND26_Shelving_Oct,desc,10/1/2026,10/31/2026,LAUNDRY,ARIEL,https://x/b.jpg,10/6/2026,Visibility
      CSV
    end

    it "parses by header, extracts the CU code from Store Name, and parses dates" do
      log = described_class.new(csv, campaign: campaign, user: nil, filename: "r.csv").call
      expect(log.status).to eq("completed")
      expect(campaign.display_evidences.count).to eq(2)
      e = campaign.display_evidences.first
      expect(e.store_id).to eq(alpha.id)
      expect(e.from_date).to eq(Date.new(2026, 10, 1))
      expect(e.photo_taken_at).to eq(Date.new(2026, 10, 5))
      expect(e.image_url).to eq("https://x/a.jpg")
    end

    it "a new upload supersedes the previous evidence" do
      described_class.new(csv, campaign: campaign, user: nil, filename: "r.csv").call
      one_row = csv.lines[0] + csv.lines[1] # header + first row only
      described_class.new(one_row, campaign: campaign, user: nil, filename: "r2.csv").call
      expect(campaign.display_evidences.count).to eq(1) # replaced, not appended
    end
  end
end
