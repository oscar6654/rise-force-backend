module Wms
  # Close a checked job to `dispatched` and feed the shipped quantities back to
  # the SFA order (picking-first: what actually shipped, net of shorts, is the
  # authoritative figure for OSB/vcsi_rise invoicing). Stamps OrderLine#shipped_qty
  # in the order line's own uom. Only after this may the OSB batch pick the order up.
  class DispatchService
    class Error < StandardError; end

    def initialize(fulfillment_order)
      @fo = fulfillment_order
    end

    def dispatch!
      raise Error, "Job must be checked before dispatch" unless @fo.checked?

      ApplicationRecord.transaction do
        stamp_shipped_quantities! if @fo.order
        @fo.update!(status: :dispatched, dispatched_at: Time.current)
      end
      @fo
    end

    private

    # Sum checked pieces per product across ALL of this order's fulfillment orders
    # (a split order has several, and one product's case + loose lines may live on
    # different children), then write each SFA order line's shipped_qty in its uom.
    # Re-stamping on each child's dispatch is fine: the last dispatch sees every
    # child's qty_checked, so the final figure is complete.
    def stamp_shipped_quantities!
      order = @fo.order
      fo_ids = FulfillmentOrder.where(order_id: order.id).ids
      checked_pieces = FulfillmentLine.where(fulfillment_order_id: fo_ids).group(:product_id).sum(:qty_checked)
      order.order_lines.where(line_type: :sale).find_each do |ol|
        pieces = checked_pieces[ol.product_id]
        next if pieces.nil?

        per_case = ol.product.pcs_per_case || 1
        ol.update!(shipped_qty: ol.uom_case_uom? ? (pieces / per_case) : pieces)
      end
    end
  end
end
