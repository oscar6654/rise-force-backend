require "rails_helper"

RSpec.describe BranchLeaderboard do
  let(:branch) { create(:branch) }
  let(:a) { create(:seller, branch: branch, name: "Rep A") }
  let(:b) { create(:seller, branch: branch, name: "Rep A (2nd branch code)", primary_seller: a) }
  let(:c) { create(:seller, branch: branch, name: "Rep C") }
  let(:month) { Date.current.beginning_of_month }

  before do
    [a, b].each do |s|
      SellerTarget.create!(seller: s, branch: branch, period_type: :mtd, period_date: month, target_amount: 100_000)
      SelloutSnapshot.create!(seller: s, branch: branch, period_type: :mtd, period_date: month, amount: 60_000)
    end
    SellerTarget.create!(seller: c, branch: branch, period_type: :mtd, period_date: month, target_amount: 100_000)
    SelloutSnapshot.create!(seller: c, branch: branch, period_type: :mtd, period_date: month, amount: 90_000)
  end

  it "ranks a login group as ONE entrant with combined metrics" do
    result = described_class.new(a).ranking("target_pct")
    ids = result[:rows].map { |r| r[:seller_id] }
    expect(ids).to contain_exactly(a.id, c.id) # B folds into A, not a separate row

    ab = result[:rows].find { |r| r[:seller_id] == a.id }
    expect(ab[:value]).to eq(60) # (60k+60k) / (100k+100k) = 60%
    expect(ab[:me]).to be(true)
  end

  it "still marks the group as 'me' when logged in as the secondary record" do
    result = described_class.new(b).ranking("target_pct")
    ab = result[:rows].find { |r| r[:seller_id] == a.id }
    expect(ab[:me]).to be(true)
  end
end
