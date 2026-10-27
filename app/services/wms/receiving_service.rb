module Wms
  # Receive scanned stock against an ASN/expected-receipt line. Matching is by
  # barcode (many itemkeys can share a barcode — the specific itemkey is the
  # receipt_line's resolved product). Short/over is flagged, never blocked.
  # Received stock lands as a `received` lot at the warehouse's receiving dock,
  # ready for putaway. Quantities are stored canonically in PIECES.
  class ReceivingService
    class Error < StandardError; end

    def initialize(receipt_line, staff: nil)
      @line = receipt_line
      @receipt = receipt_line.receipt
      @warehouse = @receipt.warehouse
      @staff = staff
    end

    # qty is in the line's uom (cases or pieces). barcode is what was scanned.
    def receive!(barcode:, qty:)
      product = resolve_product(barcode)
      raise Error, "Scanned barcode #{barcode} does not match this receipt line" unless product

      pieces = to_pieces(qty.to_d, product)
      dock = receiving_dock!

      ApplicationRecord.transaction do
        lot = InventoryLot.find_or_create_by!(
          warehouse: @warehouse, storage_location: dock, product: product,
          lot_code: @receipt.po_ref, received_date: Date.current
        ) { |l| l.status = :received }
        lot.with_lock do
          lot.update!(qty_on_hand: lot.qty_on_hand + pieces, status: :received)
        end
        Ledger.record!(warehouse: @warehouse, type: :receipt, quantity: pieces, field: :on_hand,
                       lot: lot, location: dock, product: product, staff: @staff, receipt: @receipt,
                       reason: "receive", metadata: { barcode: barcode, uom: @line.uom, qty: qty })

        @line.update!(received_qty: @line.received_qty + qty.to_d)
        @line.recompute_status!
        advance_receipt_status!
        lot
      end
    end

    private

    # The ASN line carries the pinned itemkey. Accept the scan when the scanned
    # barcode matches that product's ITEM barcode (loose/pieces) OR CASE barcode
    # (cases) — or the line's own it_barcode. If the ASN never pinned a product,
    # fall back to the barcode's representative itemkey.
    def resolve_product(barcode)
      bc = barcode.to_s.strip
      if @line.product
        p = @line.product
        p if p.it_barcode == bc || p.cs_barcode == bc || @line.it_barcode == bc
      else
        Product.representative_for(bc)
      end
    end

    def to_pieces(qty, product)
      @line.case_uom? ? qty * (product.pcs_per_case || 1) : qty
    end

    def receiving_dock!
      @warehouse.receiving_dock ||
        @warehouse.storage_locations.create!(loc_code: "DOCK", name: "Receiving dock",
                                             loc_type: :receiving_dock, pickable: false,
                                             allow_mixed_lots: true, slot_capacity: 9_999)
    end

    def advance_receipt_status!
      if @receipt.fully_received?
        @receipt.received!
      else
        @receipt.receiving! unless @receipt.received? || @receipt.closed?
      end
    end
  end
end
