module Api
  module V1
    module Wms
      # ASN / expected receipts to receive against.
      class ReceiptsController < BaseController
        before_action -> { require_staff_role!(:receive) }

        def index
          receipts = warehouse.receipts.where(status: %i[open receiving]).order(created_at: :desc)
          render json: { data: receipts.map { |r| receipt_json(r) }, meta: meta }
        end

        def show
          receipt = warehouse.receipts.find(params[:id])
          render json: { data: receipt_json(receipt, lines: true), meta: meta }
        end

        private

        def receipt_json(receipt, lines: false)
          h = { id: receipt.id, po_ref: receipt.po_ref, status: receipt.status,
                line_count: receipt.receipt_lines.size }
          if lines
            h[:lines] = receipt.receipt_lines.includes(:product).map do |l|
              { id: l.id, product_id: l.product_id, sku: l.product&.sku, description: l.product&.description,
                it_barcode: l.it_barcode || l.product&.it_barcode, cs_barcode: l.product&.cs_barcode,
                pcs_per_case: l.product&.pcs_per_case || 1, expected_qty: l.expected_qty,
                received_qty: l.received_qty, uom: l.uom, status: l.status }
            end
          end
          h
        end
      end
    end
  end
end
