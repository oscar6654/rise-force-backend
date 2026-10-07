require "rails_helper"

RSpec.describe DisplayReport do
  let(:branch) { create(:branch) }
  let(:store)  { create(:store, branch: branch, store_code: "CU_90001") }
  let(:campaign) do
    DisplayCampaign.create!(name: "OCT", period_from: Date.new(2026, 10, 1), period_to: Date.new(2026, 10, 31))
  end

  def target(promo:, category:, brand: nil)
    DisplayTarget.create!(display_campaign: campaign, store: store, store_code: "CU_90001",
                          promotion_name: promo, category: category, brand: brand)
  end

  def evidence(promo:, category:, brand: nil, from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 31),
               url: "https://x/p.jpg", taken: Date.new(2026, 10, 5))
    DisplayEvidence.create!(display_campaign: campaign, store: store, store_code: "CU_90001",
                            promotion_name: promo, category: category, brand: brand,
                            from_date: from, to_date: to, image_url: url, photo_taken_at: taken)
  end

  def line_for(promo, brand = nil)
    DisplayReport.new(campaign, store_ids: [store.id]).by_store[store.id][:lines]
                 .find { |l| l.promotion_name == promo && l.brand == brand }
  end

  it "marks a brand-specific line executed only when the brand matches" do
    target(promo: "P1", category: "LAUNDRY", brand: "ARIEL")
    evidence(promo: "P1", category: "LAUNDRY", brand: "ariel") # case-insensitive match
    expect(line_for("P1", "ARIEL").executed).to be(true)
  end

  it "does not match when the evidence brand differs" do
    target(promo: "P1", category: "LAUNDRY", brand: "ARIEL")
    evidence(promo: "P1", category: "LAUNDRY", brand: "TIDE")
    expect(line_for("P1", "ARIEL").executed).to be(false)
  end

  it "a blank-brand target is met by any brand in the category" do
    target(promo: "P2", category: "LAUNDRY", brand: nil)
    evidence(promo: "P2", category: "LAUNDRY", brand: "DOWNY")
    expect(line_for("P2").executed).to be(true)
  end

  it "ignores evidence whose window does not overlap the campaign" do
    target(promo: "P3", category: "LAUNDRY")
    evidence(promo: "P3", category: "LAUNDRY", from: Date.new(2026, 9, 1), to: Date.new(2026, 9, 30))
    expect(line_for("P3").executed).to be(false)
  end

  it "returns all matching photos, oldest-taken first, and rolls up counts" do
    target(promo: "P4", category: "LAUNDRY")
    evidence(promo: "P4", category: "LAUNDRY", url: "b.jpg", taken: Date.new(2026, 10, 9))
    evidence(promo: "P4", category: "LAUNDRY", url: "a.jpg", taken: Date.new(2026, 10, 2))
    target(promo: "P5", category: "DISH CARE") # unexecuted

    rep = DisplayReport.new(campaign, store_ids: [store.id]).by_store[store.id]
    expect(rep[:must]).to eq(2)
    expect(rep[:done]).to eq(1)
    expect(rep[:missing]).to eq(1)
    photos = line_for("P4").photos
    expect(photos.map(&:image_url)).to eq(["a.jpg", "b.jpg"]) # oldest taken first
  end

  it "excludes stores outside the given scope" do
    other = create(:store, branch: branch, store_code: "CU_90002")
    DisplayTarget.create!(display_campaign: campaign, store: other, store_code: "CU_90002",
                          promotion_name: "PX", category: "LAUNDRY")
    target(promo: "P6", category: "LAUNDRY")
    by_store = DisplayReport.new(campaign, store_ids: [store.id]).by_store
    expect(by_store.keys).to eq([store.id])
  end
end
