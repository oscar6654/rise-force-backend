require "rails_helper"

RSpec.describe "WMS short pick + cycle count" do
  let(:warehouse) { create(:warehouse) }
  let(:product)   { create(:product, pcs_per_case: 10, it_barcode: "BC1") }
  let(:staff)     { create(:warehouse_staff, warehouse: warehouse, roles: %w[pick count]) }
  let(:rack_a)    { create(:storage_location, warehouse: warehouse, loc_code: "A", pick_sequence: 1) }
  let(:rack_b)    { create(:storage_location, warehouse: warehouse, loc_code: "B", pick_sequence: 2) }

  def lot(loc, qty, received)
    create(:inventory_lot, warehouse: warehouse, product: product, storage_location: loc,
           qty_on_hand: qty, received_date: received, status: :active)
  end

  def allocated_fo(pieces)
    fo = create(:fulfillment_order, warehouse: warehouse)
    fo.fulfillment_lines.create!(product: product, qty_demanded: pieces, uom: :pc)
    Wms::AllocationService.new(fo).allocate!
    fo
  end

  it "re-sources a short pick from another location and flags IRA on the short bin" do
    lot(rack_a, 30, Date.today - 2)
    lot(rack_b, 30, Date.today - 1)
    fo = allocated_fo(30) # all 30 from rack_a (oldest)
    alloc = fo.pick_allocations.first

    Wms::PickingService.new(staff: staff).confirm!(alloc, qty_picked: 18, barcode: "BC1", location_code: "A")

    expect(alloc.reload.status).to eq("partial")
    new_alloc = fo.pick_allocations.order(:id).last
    expect(new_alloc.storage_location).to eq(rack_b)
    expect(new_alloc.qty_allocated.to_i).to eq(12)
    expect(rack_a.reload.needs_cycle_count).to be(true)
    expect(CycleCount.where(storage_location: rack_a, trigger: :pick_discrepancy).count).to eq(1)
  end

  it "close-short (can't find): flags IRA, does NOT re-source, line stays short" do
    lot(rack_a, 30, Date.today - 2)
    lot(rack_b, 30, Date.today - 1) # stock exists elsewhere, but close must NOT use it
    fo = allocated_fo(30)
    alloc = fo.pick_allocations.first

    Wms::PickingService.new(staff: staff).confirm!(alloc, qty_picked: 10, barcode: "BC1", location_code: "A", on_short: :close)

    expect(alloc.reload.status).to eq("short")
    expect(fo.pick_allocations.count).to eq(1) # no re-sourced allocation created
    expect(rack_a.reload.needs_cycle_count).to be(true)
    expect(fo.reload.status).to eq("short")
  end

  it "finish-short closes all open allocations, flags their bins, and sends to checking" do
    lot(rack_a, 30, Date.today - 2)
    lot(rack_b, 30, Date.today - 1)
    fo = allocated_fo(40) # 30 from A + 10 from B
    Wms::PickingService.new(staff: staff).start!(fo)

    Wms::PickingService.new(staff: staff).finish_short!(fo)

    expect(fo.reload.status).to eq("short")
    expect(fo.pick_allocations.pluck(:status).uniq).to eq(["short"])
    expect(rack_a.reload.needs_cycle_count).to be(true)
    expect(rack_b.reload.needs_cycle_count).to be(true)
    # reservations released back to stock
    expect(rack_a.inventory_lots.first.qty_locked.to_i).to eq(0)
  end

  it "leaves the line short when no other location has stock" do
    lot(rack_a, 30, Date.today)
    fo = allocated_fo(30)
    alloc = fo.pick_allocations.first

    Wms::PickingService.new(staff: staff).confirm!(alloc, qty_picked: 20, barcode: "BC1", location_code: "A")

    expect(fo.pick_allocations.where(status: %i[allocated locked]).count).to eq(0)
    expect(fo.reload.status).to eq("short")
  end

  it "refuses to undo a PARTIAL allocation (re-source already happened → would double-reserve)" do
    lot(rack_a, 30, Date.today - 2)
    lot(rack_b, 30, Date.today - 1)
    fo = allocated_fo(30)
    alloc = fo.pick_allocations.first
    # Pick short with the default re-source → original allocation becomes :partial
    Wms::PickingService.new(staff: staff).confirm!(alloc, qty_picked: 18, barcode: "BC1", location_code: "A")
    expect(alloc.reload.status).to eq("partial")
    expect { Wms::PickingService.new(staff: staff).undo!(alloc) }.to raise_error(Wms::PickingService::Error, /fully-picked/)
  end

  it "undo returns a picked line to the pick list (stock back, allocation re-opened)" do
    l = lot(rack_a, 50, Date.today)
    fo = allocated_fo(20)
    alloc = fo.pick_allocations.first
    Wms::PickingService.new(staff: staff).confirm!(alloc, qty_picked: 20, barcode: "BC1", location_code: "A")
    expect(fo.reload.status).to eq("picked")
    expect(l.reload.qty_on_hand.to_i).to eq(30) # 50 - 20 picked

    Wms::PickingService.new(staff: staff).undo!(alloc.reload)

    expect(alloc.reload.status).to eq("allocated")
    expect(alloc.qty_picked.to_i).to eq(0)
    expect(fo.reload.status).to eq("picking")
    expect(l.reload.qty_on_hand.to_i).to eq(50)          # stock returned
    expect(l.qty_allocated.to_i).to eq(20)                # re-reserved
    expect(fo.fulfillment_lines.first.qty_picked.to_i).to eq(0)
  end

  it "reconciles a cycle count: adjusts on_hand and records IRA variance" do
    l = lot(rack_a, 40, Date.today)
    user = create(:user)
    count = Wms::CycleCountService.open!(rack_a, trigger: :manual)
    expect(count.system_qty.to_i).to eq(40)

    Wms::CycleCountService.new(count).submit!(counted_qty: 37, staff: staff)
    expect(count.reload.variance.to_i).to eq(-3)

    Wms::CycleCountService.new(count).reconcile!(user: user)
    expect(l.reload.qty_on_hand.to_i).to eq(37)
    expect(count.reload.status).to eq("reconciled")
    expect(StockMovement.where(cycle_count: count, movement_type: :adjust).sum(:quantity).to_i).to eq(-3)
  end
end
