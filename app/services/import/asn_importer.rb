module Import
  # ASN / expected-receipt upload (re-uploadable). CSV headers:
  #   warehouse_code, po_ref, itemkey, it_barcode, expected_qty, uom
  # The ASN is keyed on ITEMKEY (the product's sku) so the EXACT itemkey is
  # pinned at receiving and travels with the lot through pick → dispatch. Barcodes
  # are only for scan-matching (it_barcode for loose/pieces, cs_barcode for cases)
  # and come from the product master. Rows grouped by [warehouse, po_ref] into a
  # Receipt + lines; re-uploading a po_ref OVERWRITES its open receipt's lines.
  class AsnImporter < BaseImporter
    include WmsHelpers
    JOB_TYPE = :asn_import

    def initialize(*args, **kwargs)
      super
      @reset_receipts = {} # [warehouse_id, po_ref] => Receipt (lines cleared once per run)
    end

    private

    def import_row(row)
      wh = warehouse_for!(row["warehouse_code"])
      po = row["po_ref"].to_s.strip
      raise "po_ref is required" if po.blank?

      receipt = receipt_for(wh, po)
      product = resolve_asn_product(row)
      receipt.receipt_lines.create!(
        product: product,
        # Keep the item barcode for scan-matching (from the row, else the master).
        it_barcode: row["it_barcode"].presence || product&.it_barcode,
        expected_qty: num(row["expected_qty"]) || 0, uom: uom_for(row["uom"])
      )
    end

    # Pin the EXACT itemkey from the ASN. itemkey (sku) is authoritative; a bare
    # barcode falls back to the representative itemkey for that barcode.
    def resolve_asn_product(row)
      key = (row["itemkey"] || row["sku"]).to_s.strip
      if key.present?
        product = Product.find_by("lower(sku) = ?", key.downcase)
        raise "unknown itemkey '#{key}'" unless product

        return product
      end
      bc = row["it_barcode"].to_s.strip
      raise "itemkey (or it_barcode) is required" if bc.blank?

      Product.representative_for(bc) || (raise "no product for barcode '#{bc}'")
    end

    # Find-or-create the receipt, clearing its open lines the first time we touch
    # it this run (the overwrite-on-reupload behaviour).
    def receipt_for(wh, po)
      key = [wh.id, po.downcase]
      return @reset_receipts[key] if @reset_receipts.key?(key)

      receipt = Receipt.find_or_create_by!(warehouse: wh, po_ref: po)
      receipt.receipt_lines.destroy_all unless receipt.closed? || receipt.received?
      receipt.update!(status: :open)
      @reset_receipts[key] = receipt
    end

    def uom_for(value)
      value.to_s.strip.downcase.in?(%w[pc pcs piece pieces]) ? :pc : :case_uom
    end
  end
end
