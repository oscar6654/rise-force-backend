require "rails_helper"

RSpec.describe Import::AsnImporter do
  let(:user) { create(:user) }
  let!(:wh)  { create(:warehouse, whs_code: "WH1") }
  let!(:product) { create(:product, sku: "KOP-A", it_barcode: "IT-A", cs_barcode: "CS-A") }

  it "pins the EXACT itemkey from the ASN and carries the item barcode from the master" do
    csv = "warehouse_code,po_ref,itemkey,expected_qty,uom\nWH1,PO1,KOP-A,80,case\n"
    described_class.new(csv, user: user).call

    line = Receipt.find_by(warehouse: wh, po_ref: "PO1").receipt_lines.first
    expect(line.product).to eq(product)      # exact itemkey, not a barcode guess
    expect(line.it_barcode).to eq("IT-A")    # filled from the product master
    expect(line.uom).to eq("case_uom")
  end

  it "rejects an unknown itemkey" do
    csv = "warehouse_code,po_ref,itemkey,expected_qty,uom\nWH1,PO2,NOPE,10,pc\n"
    log = described_class.new(csv, user: user).call
    expect(log.error_count).to eq(1)
    expect(Receipt.find_by(po_ref: "PO2")&.receipt_lines).to be_blank
  end

  it "receiving accepts the CASE barcode (not just the item barcode)" do
    receipt = wh.receipts.create!(po_ref: "PO3")
    line = receipt.receipt_lines.create!(product: product, it_barcode: "IT-A", expected_qty: 5, uom: :case_uom)
    create(:storage_location, warehouse: wh, loc_code: "DOCK", loc_type: :receiving_dock, pickable: false, allow_mixed_lots: true, slot_capacity: 999)

    lot = Wms::ReceivingService.new(line).receive!(barcode: "CS-A", qty: 2) # scanned the CASE barcode
    expect(lot.product).to eq(product)
    expect(lot.qty_on_hand.to_i).to eq(2 * (product.pcs_per_case || 1))
  end
end
