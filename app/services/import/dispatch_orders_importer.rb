module Import
  # Uploaded dispatch / sales-order demand — the MANUAL path into the WMS (vs an
  # SFA seller order, which auto-flows). Each row is a line to pick.
  # CSV headers: warehouse_code, reference_no, store_code, demand_date,
  #   delivery_date, remarks, it_barcode, quantity
  # The product is found from the ITEM BARCODE (no itemkey on the file) and the
  # QUANTITY is in pieces. The quantity is split into whole cases (picked from
  # case bins) + a sub-case remainder (loose), then FIFO allocation over that
  # barcode's stock resolves the exact itemkey (and the case barcode for case
  # lines). Rows are grouped by [warehouse, reference_no] into one FulfillmentOrder
  # (pick job); allocation + picker assignment run after the import.
  class DispatchOrdersImporter < BaseImporter
    include WmsHelpers
    JOB_TYPE = :dispatch_import

    def initialize(*args, **kwargs)
      super
      @fos = {} # [warehouse_id, reference_no] => FulfillmentOrder
    end

    # Import the rows, then allocate + assign each built fulfillment order.
    def call
      log = super
      @fos.each_value { |fo| Wms::AllocateJob.perform_later(fo.id) }
      log
    end

    private

    def import_row(row)
      wh = warehouse_for!(row["warehouse_code"])
      ref = row["reference_no"].to_s.strip
      raise "reference_no is required" if ref.blank?

      barcode = row["it_barcode"].to_s.strip
      raise "it_barcode is required" if barcode.blank?

      product = Product.representative_for(barcode)
      raise "No product found for it_barcode '#{barcode}'" unless product

      # quantity is in pieces; a `uom`/`it_quantity` column is tolerated for
      # back-compat but the file is pieces by default.
      pieces = to_pieces(row["quantity"] || row["it_quantity"], row["uom"], product)
      fo = fo_for(wh, ref, row)
      # Split full cases vs the loose remainder, exactly like the SFA auto-flow.
      Wms::DemandSplit.add_line!(fo, product, pieces)
    end

    def fo_for(wh, ref, row)
      key = [wh.id, ref.downcase]
      return @fos[key] if @fos.key?(key)

      store = row["store_code"].present? ? Store.find_by("lower(store_code) = ?", row["store_code"].to_s.strip.downcase) : nil
      fo = FulfillmentOrder.find_or_create_by!(warehouse: wh, reference_no: ref) do |f|
        f.source = :dispatch_csv
        f.status = :pending
        f.store = store
        f.demand_date = parse_date(row["demand_date"])
        f.delivery_date = parse_date(row["delivery_date"])
        f.remarks = row["remarks"].presence
        f.import_batch_uuid = @log&.id&.to_s
      end
      @fos[key] = fo
    end

    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
