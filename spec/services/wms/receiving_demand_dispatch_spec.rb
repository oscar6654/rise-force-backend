require "rails_helper"

RSpec.describe "WMS receiving → demand → dispatch" do
  let(:branch)    { create(:branch) }
  let(:warehouse) { create(:warehouse, branch: branch, wms_enabled: true) }
  let(:product)   { create(:product, pcs_per_case: 10, it_barcode: "BC1") }
  let!(:dock)     { create(:storage_location, warehouse: warehouse, loc_code: "DOCK", loc_type: :receiving_dock, pickable: false, allow_mixed_lots: true, slot_capacity: 999) }

  describe Wms::ReceivingService do
    it "receives cases into pieces on the dock and flags short vs expected" do
      receipt = warehouse.receipts.create!(po_ref: "PO1")
      line = receipt.receipt_lines.create!(product: product, it_barcode: "BC1", expected_qty: 5, uom: :case_uom)

      lot = described_class.new(line).receive!(barcode: "BC1", qty: 3)

      expect(lot.qty_on_hand.to_i).to eq(30)        # 3 cases × 10
      expect(lot.storage_location).to eq(dock)
      expect(line.reload.status).to eq("partial")   # 3 of 5 expected
    end

    it "rejects a barcode that does not match the line" do
      receipt = warehouse.receipts.create!(po_ref: "PO2")
      line = receipt.receipt_lines.create!(product: product, it_barcode: "BC1", expected_qty: 5, uom: :case_uom)
      expect { described_class.new(line).receive!(barcode: "WRONG", qty: 1) }
        .to raise_error(Wms::ReceivingService::Error)
    end
  end

  describe Wms::DemandFromOrder do
    # Seller is tied to the WMS warehouse and flagged wms_enabled → orders route to WMS.
    let(:seller) { create(:seller, branch: branch, warehouse: warehouse, wms_enabled: true) }
    let(:store)  { create(:store, branch: branch) }
    let(:rack)   { create(:storage_location, warehouse: warehouse, loc_code: "A") }

    it "builds a pick job in pieces, carries delivery_date + remarks, allocates" do
      create(:inventory_lot, warehouse: warehouse, product: product, storage_location: rack,
             qty_on_hand: 100, received_date: Date.today, status: :active)
      order = create(:order, seller: seller, store: store, branch: branch, status: :submitted,
                     delivery_date: Date.new(2026, 10, 30), notes: "AM only")
      order.order_lines.create!(product: product, quantity: 2, uom: :case_uom, unit_price: 10, line_total: 20)

      fo = described_class.new(order).call

      expect(fo.reference_no).to eq(order.order_number)
      expect(fo.delivery_date).to eq(Date.new(2026, 10, 30))
      expect(fo.remarks).to eq("AM only")
      expect(fo.fulfillment_lines.first.qty_demanded.to_i).to eq(20) # 2 cases × 10
      expect(fo.pick_allocations.sum(:qty_allocated).to_i).to eq(20)
    end

    it "is idempotent on [warehouse, reference_no]" do
      order = create(:order, seller: seller, store: store, branch: branch, status: :submitted)
      order.order_lines.create!(product: product, quantity: 1, uom: :case_uom, unit_price: 10, line_total: 10)
      first = described_class.new(order).call
      again = described_class.new(order).call
      expect(again.id).to eq(first.id)
      expect(FulfillmentOrder.where(warehouse: warehouse, reference_no: order.order_number).count).to eq(1)
    end

    it "no-ops when the seller is not WMS-routed (no warehouse / flag off)" do
      plain = create(:seller, branch: branch) # no warehouse, wms_enabled false
      order = create(:order, seller: plain, store: store, branch: branch, status: :submitted)
      expect(described_class.new(order).call).to be_nil
    end

    it "no-ops when the seller's warehouse itself has WMS off" do
      non_wms_wh = create(:warehouse, branch: branch, wms_enabled: false)
      s = create(:seller, branch: branch, warehouse: non_wms_wh, wms_enabled: true)
      order = create(:order, seller: s, store: store, branch: branch, status: :submitted)
      expect(described_class.new(order).call).to be_nil
    end
  end

  describe Wms::DispatchService do
    let(:seller) { create(:seller, branch: branch, warehouse: warehouse, wms_enabled: true) }
    let(:store)  { create(:store, branch: branch) }
    let(:rack)   { create(:storage_location, warehouse: warehouse, loc_code: "A") }
    let(:staff)  { create(:warehouse_staff, warehouse: warehouse, roles: %w[pick check]) }

    it "stamps shipped_qty back on the order line in cases (net of shorts)" do
      create(:inventory_lot, warehouse: warehouse, product: product, storage_location: rack,
             qty_on_hand: 100, received_date: Date.today, status: :active)
      order = create(:order, seller: seller, store: store, branch: branch, status: :submitted)
      ol = order.order_lines.create!(product: product, quantity: 3, uom: :case_uom, unit_price: 10, line_total: 30)
      fo = Wms::DemandFromOrder.new(order).call # 30 pcs
      alloc = fo.pick_allocations.first

      Wms::PickingService.new(staff: staff).confirm!(alloc, qty_picked: 25, barcode: "BC1",
                                                     location_code: "A", find_elsewhere: false)
      fo.fulfillment_lines.each { |l| Wms::CheckingService.new(staff: staff).verify!(l, qty_checked: l.qty_picked) }
      Wms::CheckingService.new(staff: staff).complete!(fo.reload)
      Wms::DispatchService.new(fo.reload).dispatch!

      expect(fo.reload.status).to eq("dispatched")
      expect(ol.reload.shipped_qty.to_f).to eq(2.5) # 25 pcs / 10 per case
    end
  end
end
