require "rails_helper"

RSpec.describe "StockMovement.filtered (audit trail)" do
  let(:warehouse)  { create(:warehouse) }
  let(:warehouse2) { create(:warehouse) }
  let(:product)    { create(:product) }
  let(:staff)      { create(:warehouse_staff, warehouse: warehouse, staff_code: "PICKER1", roles: %w[pick]) }

  def movement(type:, at:, wh: warehouse, by_staff: nil)
    StockMovement.create!(warehouse: wh, product: product, movement_type: type,
                          field: :on_hand, quantity: -1, warehouse_staff: by_staff, occurred_at: at)
  end

  it "filters by an inclusive from/to date window on occurred_at" do
    old   = movement(type: :pick, at: Time.zone.parse("2026-01-01 09:00"))
    mid   = movement(type: :pick, at: Time.zone.parse("2026-01-10 23:30"))
    newer = movement(type: :pick, at: Time.zone.parse("2026-01-20 00:30"))

    result = StockMovement.filtered(from: "2026-01-10", to: "2026-01-10")
    expect(result).to contain_exactly(mid) # end-of-day bound keeps the 23:30 row
    expect(result).not_to include(old, newer)

    windowed = StockMovement.filtered(from: "2026-01-01", to: "2026-01-20")
    expect(windowed).to contain_exactly(old, mid, newer)
  end

  it "filters by warehouse, movement_type and staff_code" do
    mine  = movement(type: :pick, at: Time.current, by_staff: staff)
    other = create(:warehouse_staff, warehouse: warehouse, staff_code: "PICKER2", roles: %w[pick])
    movement(type: :pick, at: Time.current, by_staff: other)
    movement(type: :putaway, at: Time.current, by_staff: staff)
    movement(type: :pick, at: Time.current, wh: warehouse2, by_staff: staff)

    result = StockMovement.filtered(warehouse_id: warehouse.id, movement_type: "pick", staff_code: "PICKER1")
    expect(result).to contain_exactly(mine)
  end

  it "ignores blank and malformed dates (no bound applied)" do
    m = movement(type: :pick, at: Time.current)
    expect(StockMovement.filtered(from: "", to: "not-a-date")).to include(m)
  end
end
