require "rails_helper"

RSpec.describe "WMS piece-pick split + replenishment" do
  let(:branch)    { create(:branch) }
  let(:warehouse) { create(:warehouse, branch: branch, wms_enabled: true, piece_pick_zone: "LOOSE") }
  let(:brand)     { create(:brand) }
  let(:product)   { create(:product, brand: brand, pcs_per_case: 30, it_barcode: "IT", cs_barcode: "CS") }
  let!(:case_rack)  { create(:storage_location, warehouse: warehouse, loc_code: "A-1", zone: "A") }
  let!(:piece_loc)  { create(:storage_location, warehouse: warehouse, loc_code: "L-1", zone: "LOOSE", allow_mixed_lots: true, slot_capacity: 50) }
  let(:seller) { create(:seller, branch: branch, warehouse: warehouse, wms_enabled: true) }
  let(:store)  { create(:store, branch: branch) }

  def order_for(pieces)
    o = create(:order, seller: seller, store: store, branch: branch, status: :submitted)
    o.order_lines.create!(product: product, quantity: pieces, uom: :pc, unit_price: 1, line_total: pieces)
    o
  end

  it "splits a mixed demand into a full-case line and a loose line" do
    create(:inventory_lot, warehouse: warehouse, product: product, storage_location: case_rack, qty_on_hand: 90, status: :active)
    create(:inventory_lot, warehouse: warehouse, product: product, storage_location: piece_loc, qty_on_hand: 50, status: :active)
    fo = Wms::DemandFromOrder.new(order_for(40)).call # 40 pc = 30 case + 10 loose

    lines = FulfillmentLine.where(fulfillment_order_id: [fo.id, *fo.child_fulfillment_orders.ids])
    cs = lines.find(&:pack_case?)
    loose = lines.find(&:pack_loose?)
    expect(cs.qty_demanded.to_i).to eq(30)
    expect(loose.qty_demanded.to_i).to eq(10)
    # case line sourced from the case rack, loose line from the piece zone
    expect(cs.pick_allocations.first.storage_location).to eq(case_rack)
    expect(loose.pick_allocations.first.storage_location).to eq(piece_loc)
  end

  it "raises an auto replenishment task when the piece zone is short, then fills on execute" do
    create(:inventory_lot, warehouse: warehouse, product: product, storage_location: case_rack, qty_on_hand: 90, status: :active)
    create(:inventory_lot, warehouse: warehouse, product: product, storage_location: piece_loc, qty_on_hand: 5, status: :active)
    fo = Wms::DemandFromOrder.new(order_for(40)).call # loose needs 10, only 5 in piece zone

    task = ReplenishmentTask.find_by(warehouse: warehouse, product: product)
    expect(task).to be_present
    expect(task.qty_cases).to eq(1) # ceil(5 short / 30)
    expect(task.piece_location).to eq(piece_loc)

    loose = FulfillmentLine.where(fulfillment_order_id: [fo.id, *fo.child_fulfillment_orders.ids]).find(&:pack_loose?)
    expect(loose.status).to eq("short")

    Wms::ReplenishmentService.new(warehouse).execute!(task)

    expect(task.reload.status).to eq("done")
    expect(loose.reload.status).to eq("allocated")
    expect(loose.qty_allocated.to_i).to eq(10)
  end

  it "manual drop breaks cases into the piece zone" do
    create(:inventory_lot, warehouse: warehouse, product: product, storage_location: case_rack, qty_on_hand: 90, status: :active)
    moved = Wms::ReplenishmentService.new(warehouse).manual!(product: product, qty_cases: 2)
    expect(moved.to_i).to eq(60)
    expect(piece_loc.inventory_lots.sum(:qty_on_hand).to_i).to eq(60)
  end
end
