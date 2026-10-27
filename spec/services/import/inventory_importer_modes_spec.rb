require "rails_helper"

RSpec.describe "Import::InventoryImporter upload modes" do
  let(:user)    { create(:user) }
  let(:wh)      { create(:warehouse, whs_code: "WH1") }
  let(:prod_a)  { create(:product, sku: "ITEM-A", pcs_per_case: 10) }
  let(:prod_b)  { create(:product, sku: "ITEM-B", pcs_per_case: 10) }
  let(:loc_a)   { create(:storage_location, warehouse: wh, loc_code: "A-01") }
  let(:loc_b)   { create(:storage_location, warehouse: wh, loc_code: "B-01") }

  # File sets ITEM-A @ A-01 to 25 pc. ITEM-B @ B-01 (40 on hand) is NOT in the file.
  def csv
    <<~CSV
      warehouse_code,loc_code,itemkey,it_barcode,lot_code,received_date,expiry_date,qty_on_hand,uom
      WH1,A-01,ITEM-A,,LOT-A,2026-10-01,,25,pc
    CSV
  end

  before do
    prod_a; loc_a; loc_b # ensure ITEM-A exists so the file row resolves
    create(:inventory_lot, warehouse: wh, product: prod_b, storage_location: loc_b,
           lot_code: "LOT-B", received_date: "2026-09-01", qty_on_hand: 40, status: :active)
  end

  it "adjust/append mode (default): sets listed lot, leaves others untouched" do
    Import::InventoryImporter.new(csv, user: user).call

    a = InventoryLot.find_by(product: prod_a, storage_location: loc_a)
    b = InventoryLot.find_by(product: prod_b, storage_location: loc_b)
    expect(a.qty_on_hand.to_i).to eq(25)
    expect(b.qty_on_hand.to_i).to eq(40) # untouched
    expect(StockMovement.where(movement_type: :adjust, reason: "inventory upload").count).to eq(1)
  end

  it "replace/refresh mode: sets listed lot AND zeroes free stock not in the file" do
    Import::InventoryImporter.new(csv, user: user, mode: "replace").call

    a = InventoryLot.find_by(product: prod_a, storage_location: loc_a)
    b = InventoryLot.find_by(product: prod_b, storage_location: loc_b)
    expect(a.qty_on_hand.to_i).to eq(25)
    expect(b.qty_on_hand.to_i).to eq(0) # zeroed — wasn't in the file
    expect(StockMovement.where(movement_type: :adjust, reason: "inventory refresh (not in file)").count).to eq(1)
  end

  it "replace mode keeps reserved (allocated/locked) stock — only the free portion drops" do
    b = InventoryLot.find_by(product: prod_b, storage_location: loc_b)
    b.update!(qty_allocated: 15) # 15 reserved of 40

    Import::InventoryImporter.new(csv, user: user, mode: "replace").call
    expect(b.reload.qty_on_hand.to_i).to eq(15) # floored to the reservation, not 0
  end

  it "replace mode does not touch other warehouses absent from the file" do
    other = create(:warehouse, whs_code: "WH2")
    oloc  = create(:storage_location, warehouse: other, loc_code: "X-01")
    olot  = create(:inventory_lot, warehouse: other, product: prod_b, storage_location: oloc,
                   received_date: "2026-09-01", qty_on_hand: 99, status: :active)

    Import::InventoryImporter.new(csv, user: user, mode: "replace").call
    expect(olot.reload.qty_on_hand.to_i).to eq(99)
  end
end
