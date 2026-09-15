require "rails_helper"

RSpec.describe Store do
  describe "#due_on?" do
    let(:monday) { Date.new(2026, 9, 7) }   # week 1, Monday
    let(:tuesday) { Date.new(2026, 9, 8) }  # week 2, Tuesday
    let(:third_monday) { Date.new(2026, 9, 21) } # week 3, Monday

    it "F4 every_week is due on its visit day every week" do
      store = build(:store, visit_frequency: :f4, week_pattern: :every_week, visit_day: :mon)
      expect(store.due_on?(monday)).to be(true)
      expect(store.due_on?(tuesday)).to be(false)
    end

    it "F2 weeks_1_3 is due in weeks 1 and 3 only" do
      store = build(:store, visit_frequency: :f2, week_pattern: :weeks_1_3, visit_day: :mon)
      expect(store.due_on?(monday)).to be(true)          # week 1
      expect(store.due_on?(third_monday)).to be(true)    # week 3
      expect(store.due_on?(Date.new(2026, 9, 14))).to be(false) # week 2 Monday
    end

    it "is never due without a visit day" do
      store = build(:store, visit_day: nil)
      expect(store.due_on?(monday)).to be(false)
    end
  end

  it "requires a store or provisional code" do
    store = build(:store, store_code: nil, provisional_code: nil)
    expect(store).not_to be_valid
  end
end
