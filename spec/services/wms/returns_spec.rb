require "rails_helper"

RSpec.describe "WMS returns (CSV + disposition + suggested location)" do
  let(:user) { create(:user) }
  let!(:wh)  { create(:warehouse, whs_code: "WH1", piece_pick_zone: "LOOSE") }
  let!(:product) { create(:product, sku: "KOP-A", it_barcode: "IT-A", pcs_per_case: 10) }
  let!(:pick_rack) { create(:storage_location, warehouse: wh, loc_code: "A-1", zone: "A") }
  let!(:loose_loc) { create(:storage_location, warehouse: wh, loc_code: "L-1", zone: "LOOSE", allow_mixed_lots: true, slot_capacity: 50) }
  let!(:damage_loc) { create(:storage_location, warehouse: wh, loc_code: "DMG", loc_type: :damage, pickable: false, allow_mixed_lots: true, slot_capacity: 50) }

  it "imports a returns CSV keyed on itemkey" do
    csv = "warehouse_code,ref,itemkey,qty,uom\nWH1,RET1,KOP-A,3,case\nWH1,RET1,KOP-A,8,pc\n"
    Import::ReturnsImporter.new(csv, user: user).call
    ret = WmsReturn.find_by(warehouse: wh, ref: "RET1")
    expect(ret.wms_return_lines.count).to eq(2)
    expect(ret.wms_return_lines.map(&:product).uniq).to eq([product])
  end

  it "suggests the damage zone for damaged/quarantine and a saleable slot otherwise" do
    expect(Wms::ReturnService.suggest_location(wh, product, "damaged")).to eq(damage_loc)
    expect(Wms::ReturnService.suggest_location(wh, product, "quarantine")).to eq(damage_loc)
    # saleable loose → the piece zone
    expect(Wms::ReturnService.suggest_location(wh, product, "saleable", loose: true)).to eq(loose_loc)
    # saleable case → a putaway slot (accepting pick rack)
    expect(Wms::ReturnService.suggest_location(wh, product, "saleable", loose: false)).to eq(pick_rack)
  end

  it "processes a return line: applies the disposition and drops at a location" do
    ret = wh.wms_returns.create!(ref: "RET2")
    line = ret.wms_return_lines.create!(product: product, qty: 2, uom: :case_uom) # 20 pc
    loc = Wms::ReturnService.suggest_location(wh, product, "damaged")
    Wms::ReturnService.new(wh, user: user).record!(product: product, qty: line.pieces, disposition: "damaged", location: loc, reason: "ret")
    lot = damage_loc.inventory_lots.first
    expect(lot.qty_on_hand.to_i).to eq(20)
    expect(lot.status).to eq("damaged")
    expect(InventoryLot.available.for_product(product).where(warehouse: wh)).to be_empty # damaged excluded
  end
end
