module Wms
  # Turn an SFA order into a WMS fulfillment order (pick job) when its branch's
  # warehouse is WMS-enabled. Quantities are converted to canonical PIECES.
  # Carries the order's delivery_date + remarks. Idempotent on
  # [warehouse, reference_no]; allocation + picker assignment run after build.
  class DemandFromOrder
    def initialize(order)
      @order = order
    end

    # Returns the FulfillmentOrder (nil when the order's seller isn't WMS-routed).
    def call
      warehouse = resolve_warehouse
      return nil unless warehouse&.wms_enabled?

      fo = FulfillmentOrder.find_or_initialize_by(warehouse: warehouse, reference_no: @order.order_number)
      return fo unless fo.new_record? # already ingested

      ApplicationRecord.transaction do
        fo.assign_attributes(
          order: @order, store: @order.store, source: :sfa_order, status: :pending,
          delivery_date: @order.delivery_date, remarks: @order.notes, demand_date: @order.ordered_at&.to_date
        )
        fo.save!
        build_lines!(fo)
      end
      Wms::AllocationService.new(fo).allocate!
      Wms::PickerAssigner.new(fo).assign!
      fo
    end

    private

    def build_lines!(fo)
      @order.order_lines.where(line_type: :sale).includes(:product).each do |ol|
        c = ol.product.pcs_per_case || 1
        pieces = ol.uom_case_uom? ? ol.quantity * c : ol.quantity
        Wms::DemandSplit.add_line!(fo, ol.product, pieces)
      end
    end

    # The seller's assigned warehouse — but only when that seller is WMS-routed
    # (seller.wms_enabled AND the warehouse has WMS on). Non-WMS sellers get nil
    # here, so their orders stay on the OSB batch-download path, untouched.
    def resolve_warehouse
      seller = @order.seller
      seller&.wms_order_routing? ? seller.warehouse : nil
    end
  end
end
