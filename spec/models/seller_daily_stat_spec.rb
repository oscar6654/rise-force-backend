require "rails_helper"

RSpec.describe SellerDailyStat do
  let(:seller) { create(:seller) }
  let(:today) { Date.new(2026, 9, 12) }

  def day(date, planned:, visited:)
    described_class.record_day!(seller, date, planned: planned, visited: visited,
                                              productive_calls: 0, orders_count: 0)
  end

  describe ".record_day!" do
    it "marks the goal met only when every planned store is visited" do
      expect(day(today, planned: 5, visited: 5).goal_met).to be(true)
      expect(day(today, planned: 5, visited: 4).goal_met).to be(false) # upserts same row
    end

    it "is not met on a day with no planned stores" do
      expect(day(today, planned: 0, visited: 0).goal_met).to be(false)
    end

    it "upserts one row per seller per day" do
      day(today, planned: 3, visited: 3)
      day(today, planned: 3, visited: 1)
      expect(described_class.where(seller: seller, stat_date: today).count).to eq(1)
    end
  end

  describe ".streak_stats" do
    it "counts consecutive completed working-days up to today" do
      day(today - 2, planned: 4, visited: 4)
      day(today - 1, planned: 4, visited: 4)
      day(today, planned: 4, visited: 4)
      expect(described_class.streak_stats(seller, today: today)).to eq(current: 3, best: 3)
    end

    it "does not break the streak on rest days (no planned stores)" do
      day(today - 3, planned: 4, visited: 4)
      day(today - 2, planned: 0, visited: 0) # rest day — skipped, not a break
      day(today - 1, planned: 4, visited: 4)
      expect(described_class.streak_stats(seller, today: today - 1)[:current]).to eq(2)
    end

    it "treats an in-progress today (goal not yet met) as 0 without breaking prior run" do
      day(today - 1, planned: 4, visited: 4)
      day(today, planned: 4, visited: 2) # still working
      expect(described_class.streak_stats(seller, today: today)[:current]).to eq(1)
    end

    it "reports the best run even after the current streak resets" do
      day(today - 4, planned: 4, visited: 4)
      day(today - 3, planned: 4, visited: 4)
      day(today - 2, planned: 4, visited: 4)
      day(today - 1, planned: 4, visited: 1) # missed → resets
      day(today, planned: 4, visited: 4)
      expect(described_class.streak_stats(seller, today: today)).to eq(current: 1, best: 3)
    end
  end
end
