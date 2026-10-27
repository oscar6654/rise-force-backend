require "rails_helper"

RSpec.describe Wms::PickerAssigner do
  let(:warehouse) { create(:warehouse, allocation_strategy: :brand_per_picker) }
  let(:brand)     { create(:brand) }
  let(:product)   { create(:product, brand: brand) }
  let(:rack)      { create(:storage_location, warehouse: warehouse) }

  def online!(staff, at: Time.current)
    DeviceToken.create!(warehouse_staff: staff, role: "staff", jti: SecureRandom.uuid, device_id: "d-#{staff.id}", last_used_at: at)
  end

  def allocated_fo
    create(:inventory_lot, warehouse: warehouse, product: product, storage_location: rack, qty_on_hand: 100, status: :active)
    fo = create(:fulfillment_order, warehouse: warehouse)
    fo.fulfillment_lines.create!(product: product, qty_demanded: 10, uom: :pc)
    Wms::AllocationService.new(fo).allocate!
    fo
  end

  it "assigns to an ONLINE picker who owns the brand" do
    picker = create(:warehouse_staff, warehouse: warehouse, roles: %w[pick], brand_ids: [brand.id])
    online!(picker)
    fo = allocated_fo
    described_class.new(fo).assign!
    expect(fo.reload.assigned_to).to eq(picker)
  end

  it "leaves the job UNASSIGNED when the only eligible picker is offline" do
    create(:warehouse_staff, warehouse: warehouse, roles: %w[pick], brand_ids: [brand.id]) # no device token → offline
    fo = allocated_fo
    described_class.new(fo).assign!
    expect(fo.reload.assigned_to).to be_nil
  end

  it "treats a stale (beyond the presence window) session as offline" do
    picker = create(:warehouse_staff, warehouse: warehouse, roles: %w[pick], brand_ids: [brand.id])
    online!(picker, at: 2.hours.ago)
    fo = allocated_fo
    described_class.new(fo).assign!
    expect(fo.reload.assigned_to).to be_nil
  end

  it "leaves the WHOLE job unassigned (no partial split) when one line has no eligible picker" do
    other_brand = create(:brand)
    other_product = create(:product, brand: other_brand)
    other_rack = create(:storage_location, warehouse: warehouse, loc_code: "O")
    create(:inventory_lot, warehouse: warehouse, product: product, storage_location: rack, qty_on_hand: 100, status: :active)
    create(:inventory_lot, warehouse: warehouse, product: other_product, storage_location: other_rack, qty_on_hand: 100, status: :active)
    online!(create(:warehouse_staff, warehouse: warehouse, roles: %w[pick], brand_ids: [brand.id])) # owns `brand` only

    fo = create(:fulfillment_order, warehouse: warehouse)
    fo.fulfillment_lines.create!(product: product, qty_demanded: 10, uom: :pc)       # ownable
    fo.fulfillment_lines.create!(product: other_product, qty_demanded: 10, uom: :pc) # NObody owns this brand
    Wms::AllocationService.new(fo).allocate!
    described_class.new(fo).assign!

    expect(fo.reload.assigned_to).to be_nil
    expect(fo.child_fulfillment_orders).to be_empty            # not split
    expect(fo.status).to be_in(%w[allocated short])            # stays sweepable by AssignUnassignedJob
  end

  it "AssignUnassignedJob picks up queued jobs once a picker comes online" do
    picker = create(:warehouse_staff, warehouse: warehouse, roles: %w[pick], brand_ids: [brand.id])
    fo = allocated_fo
    described_class.new(fo).assign!
    expect(fo.reload.assigned_to).to be_nil

    online!(picker)
    Wms::AssignUnassignedJob.new.perform(warehouse.id)
    expect(fo.reload.assigned_to).to eq(picker)
  end
end
