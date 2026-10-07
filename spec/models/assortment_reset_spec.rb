require "rails_helper"

# Per-assortment reset cycle: monthly (1) / quarterly (3) / half-year (6).
RSpec.describe "Assortment reset cycle" do
  let(:branch) { create(:branch) }
  let(:store)  { create(:store, branch: branch, vcsi_customer_ref: "C1") }
  let(:type)   { create(:assortment_type, code: "dist", name: "Distribution") }

  def must_stock!(barcode, reset_months:)
    a = create(:assortment, assortment_type: type, reset_months: reset_months)
    p = create(:product, it_barcode: barcode)
    a.assortment_items.create!(product: p, must_stock: true)
    p
  end

  # Nov 15 2026 is inside OND; the quarter started Oct 1, the month Nov 1.
  let(:on)         { Date.new(2026, 11, 15) }
  let(:qtr_start)  { Date.new(2026, 10, 1) }

  it "a quarterly target counts a SKU sold earlier in the quarter; a monthly one does not" do
    monthly = must_stock!("BM", reset_months: 1)
    quarterly = must_stock!("BQ", reset_months: 3)
    # Both SKUs were sold in October (confirmed) — earlier this quarter, last month.
    StoreSkuSellout.create!(store: store, it_barcode: "BM", period_date: qtr_start, pieces: 5)
    StoreSkuSellout.create!(store: store, it_barcode: "BQ", period_date: qtr_start, pieces: 5)

    c = store.assortment_compliance(type_code: "dist", on: on)
    expect(c[:must]).to eq(2)
    expect(c[:carried]).to eq(1)                 # only the quarterly SKU still counts
    expect(c[:gap_product_ids]).to eq([monthly.id]) # the monthly target reset this month
  end

  it "validates the reset period is 1, 3 or 6" do
    a = build(:assortment, assortment_type: type, reset_months: 2)
    expect(a).not_to be_valid
    expect(a.errors[:reset_months]).to be_present
  end

  it "computes calendar-aligned window starts" do
    expect(Assortment.window_start_for(1, Date.new(2026, 11, 15)).to_date).to eq(Date.new(2026, 11, 1))
    expect(Assortment.window_start_for(3, Date.new(2026, 11, 15)).to_date).to eq(Date.new(2026, 10, 1))
    expect(Assortment.window_start_for(6, Date.new(2026, 11, 15)).to_date).to eq(Date.new(2026, 7, 1))
    expect(Assortment.window_start_for(6, Date.new(2026, 3, 15)).to_date).to eq(Date.new(2026, 1, 1))
  end
end
