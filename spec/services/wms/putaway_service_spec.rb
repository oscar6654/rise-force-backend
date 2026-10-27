require "rails_helper"

RSpec.describe Wms::PutawayService do
  let(:warehouse) { create(:warehouse) }
  let(:brand)     { create(:brand) }
  let(:product)   { create(:product, brand: brand, abc_class: "A") }
  let(:dock)      { create(:storage_location, warehouse: warehouse, loc_code: "DOCK", loc_type: :receiving_dock, pickable: false, allow_mixed_lots: true, slot_capacity: 999) }

  def dock_lot(qty = 40)
    create(:inventory_lot, warehouse: warehouse, product: product, storage_location: dock,
           qty_on_hand: qty, status: :received)
  end

  it "suggests an accepting empty rack nearest by pick_sequence" do
    far  = create(:storage_location, warehouse: warehouse, loc_code: "FAR", pick_sequence: 9, allowed_abc_classes: ["A"])
    near = create(:storage_location, warehouse: warehouse, loc_code: "NEAR", pick_sequence: 1, allowed_abc_classes: ["A"])
    expect(described_class.new(dock_lot).suggest).to eq(near)
    _ = far
  end

  it "filters out locations that do not accept the SKU's brand" do
    other_brand = create(:brand)
    wrong = create(:storage_location, warehouse: warehouse, loc_code: "WRONG", allowed_brand_ids: [other_brand.id])
    right = create(:storage_location, warehouse: warehouse, loc_code: "RIGHT", allowed_brand_ids: [brand.id])
    expect(described_class.new(dock_lot).candidates).to eq([right])
    _ = wrong
  end

  it "skips an occupied mono-lot rack (occupied-until-zero)" do
    rack = create(:storage_location, warehouse: warehouse, loc_code: "R1", slot_capacity: 1)
    create(:inventory_lot, warehouse: warehouse, product: create(:product), storage_location: rack, qty_on_hand: 5)
    expect(described_class.new(dock_lot).candidates).not_to include(rack)
  end

  it "routes high-value brands to high_value shelves only" do
    brand.update!(high_value: true)
    hv = create(:storage_location, warehouse: warehouse, loc_code: "HV", loc_type: :high_value, allow_mixed_lots: true, slot_capacity: 10)
    create(:storage_location, warehouse: warehouse, loc_code: "RACK", loc_type: :pick_rack)
    expect(described_class.new(dock_lot).candidates).to eq([hv])
  end

  it "moves the whole lot into the chosen location and marks it active" do
    rack = create(:storage_location, warehouse: warehouse, loc_code: "R1")
    lot = dock_lot(40)
    described_class.new(lot).putaway!(location: rack)
    expect(lot.reload.storage_location).to eq(rack)
    expect(lot.status).to eq("active")
    expect(rack.has_free_slot?).to be(false)
  end
end
