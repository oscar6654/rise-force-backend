require "rails_helper"

RSpec.describe "Import::DispatchOrdersImporter (manual pick-job upload)" do
  let(:user)  { create(:user) }
  let(:wh)    { create(:warehouse, whs_code: "WH1", piece_pick_zone: "LOOSE") }
  let(:prod)  { create(:product, sku: "ITEM-X", it_barcode: "BCX", pcs_per_case: 12) }
  let(:store) { create(:store, store_code: "ST1") }

  before { wh; prod; store }

  def run(csv)
    Import::DispatchOrdersImporter.new(csv, user: user).call
  end

  it "identifies the item by barcode only (no itemkey) and resolves the product" do
    run(<<~CSV)
      warehouse_code,reference_no,store_code,it_barcode,quantity
      WH1,DSP-1,ST1,BCX,120
    CSV

    fo = FulfillmentOrder.find_by(reference_no: "DSP-1")
    expect(fo).to be_present
    expect(fo.source).to eq("dispatch_csv")
    expect(fo.store).to eq(store)
    expect(fo.fulfillment_lines.map(&:product).uniq).to eq([prod]) # found via barcode
  end

  it "splits the piece quantity into whole cases + a loose remainder" do
    run(<<~CSV)
      warehouse_code,reference_no,store_code,it_barcode,quantity
      WH1,DSP-2,ST1,BCX,30
    CSV

    fo = FulfillmentOrder.find_by(reference_no: "DSP-2")
    lines = fo.fulfillment_lines.order(:pack)
    case_line  = fo.fulfillment_lines.find(&:pack_case?)
    loose_line = fo.fulfillment_lines.find(&:pack_loose?)
    expect(case_line.qty_demanded.to_i).to eq(24)  # 2 full cases of 12
    expect(loose_line.qty_demanded.to_i).to eq(6)  # sub-case remainder
    expect(lines.sum { |l| l.qty_demanded.to_i }).to eq(30)
  end

  it "groups rows sharing a reference_no into one pick job" do
    run(<<~CSV)
      warehouse_code,reference_no,store_code,it_barcode,quantity
      WH1,DSP-3,ST1,BCX,24
      WH1,DSP-3,ST1,BCX,12
    CSV

    expect(FulfillmentOrder.where(reference_no: "DSP-3").count).to eq(1)
  end

  it "rejects a row whose barcode matches no product" do
    log = run(<<~CSV)
      warehouse_code,reference_no,store_code,it_barcode,quantity
      WH1,DSP-4,ST1,NOPE,12
    CSV
    expect(log.error_count).to eq(1)
    expect(FulfillmentOrder.find_by(reference_no: "DSP-4")).to be_nil
  end
end
