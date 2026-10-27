module Import
  # Returns upload (like the ASN, keyed on ITEMKEY). CSV headers:
  #   warehouse_code, ref, store_code, itemkey, it_barcode, qty, uom
  # Rows grouped by [warehouse, ref] into a WmsReturn + lines (disposition left
  # UNTAGGED — the operator tags saleable/damaged/quarantine when processing, and
  # the system then suggests where to drop it). Re-uploading a ref overwrites its
  # still-open lines.
  class ReturnsImporter < BaseImporter
    include WmsHelpers
    JOB_TYPE = :return_import

    def initialize(*args, **kwargs)
      super
      @seen = {} # [warehouse_id, ref] => WmsReturn
    end

    private

    def import_row(row)
      wh = warehouse_for!(row["warehouse_code"])
      ref = row["ref"].to_s.strip
      raise "ref is required" if ref.blank?

      ret = return_for(wh, ref, row)
      product = resolve_product(row)
      ret.wms_return_lines.create!(
        product: product, it_barcode: row["it_barcode"].presence || product&.it_barcode,
        qty: num(row["qty"]) || 0, uom: uom_for(row["uom"])
      )
    end

    def resolve_product(row)
      key = (row["itemkey"] || row["sku"]).to_s.strip
      if key.present?
        p = Product.find_by("lower(sku) = ?", key.downcase)
        raise "unknown itemkey '#{key}'" unless p

        return p
      end
      bc = row["it_barcode"].to_s.strip
      raise "itemkey (or it_barcode) is required" if bc.blank?

      Product.representative_for(bc) || (raise "no product for barcode '#{bc}'")
    end

    def return_for(wh, ref, row)
      key = [wh.id, ref.downcase]
      return @seen[key] if @seen.key?(key)

      store = row["store_code"].present? ? Store.find_by("lower(store_code) = ?", row["store_code"].to_s.strip.downcase) : nil
      ret = WmsReturn.find_or_create_by!(warehouse: wh, ref: ref) { |r| r.store = store }
      ret.wms_return_lines.where(status: :pending).destroy_all unless ret.closed?
      ret.update!(status: :open, store: store || ret.store)
      @seen[key] = ret
    end

    def uom_for(value)
      value.to_s.strip.downcase.in?(%w[pc pcs piece pieces]) ? :pc : :case_uom
    end
  end
end
