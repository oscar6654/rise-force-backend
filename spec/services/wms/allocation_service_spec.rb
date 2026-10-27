require "rails_helper"

RSpec.describe Wms::AllocationService do
  let(:warehouse) { create(:warehouse) }
  let(:product)   { create(:product, pcs_per_case: 10) }
  let(:rack_a)    { create(:storage_location, warehouse: warehouse, loc_code: "A", pick_sequence: 1) }
  let(:rack_b)    { create(:storage_location, warehouse: warehouse, loc_code: "B", pick_sequence: 2) }

  def lot(location, qty, received)
    create(:inventory_lot, warehouse: warehouse, product: product, storage_location: location,
           qty_on_hand: qty, received_date: received, status: :active)
  end

  def fo_for(pieces)
    fo = create(:fulfillment_order, warehouse: warehouse)
    fo.fulfillment_lines.create!(product: product, qty_demanded: pieces, uom: :pc)
    fo
  end

  it "consumes oldest lots first (FIFO) across locations" do
    old = lot(rack_a, 30, Date.today - 3)
    new = lot(rack_b, 30, Date.today - 1)
    fo = fo_for(40)

    described_class.new(fo).allocate!

    allocs = fo.pick_allocations.order(:id)
    expect(allocs.map(&:inventory_lot_id)).to eq([old.id, new.id])
    expect(allocs.map { |a| a.qty_allocated.to_i }).to eq([30, 10])
    expect(old.reload.qty_allocated.to_i).to eq(30)
    expect(new.reload.qty_allocated.to_i).to eq(10)
    expect(fo.reload.status).to eq("allocated")
  end

  it "marks the line + order short when stock is insufficient" do
    lot(rack_a, 15, Date.today)
    fo = fo_for(40)

    described_class.new(fo).allocate!

    expect(fo.fulfillment_lines.first.status).to eq("short")
    expect(fo.reload.status).to eq("short")
    expect(fo.pick_allocations.sum(:qty_allocated).to_i).to eq(15)
  end

  it "excludes stock in non-pickable (buffer) locations" do
    buffer = create(:storage_location, warehouse: warehouse, loc_code: "BUF", loc_type: :buffer, pickable: false)
    lot(buffer, 100, Date.today)
    fo = fo_for(20)

    described_class.new(fo).allocate!

    expect(fo.pick_allocations).to be_empty
    expect(fo.fulfillment_lines.first.status).to eq("short")
  end

  it "is idempotent — re-running does not double-allocate" do
    lot(rack_a, 50, Date.today)
    fo = fo_for(30)

    described_class.new(fo).allocate!
    described_class.new(fo).allocate!

    expect(fo.pick_allocations.sum(:qty_allocated).to_i).to eq(30)
    expect(rack_a.inventory_lots.first.reload.qty_allocated.to_i).to eq(30)
  end
end
