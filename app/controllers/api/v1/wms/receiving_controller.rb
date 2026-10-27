module Api
  module V1
    module Wms
      # Scan + receive stock against an ASN line.
      class ReceivingController < BaseController
        before_action -> { require_staff_role!(:receive) }

        # POST wms/receiving/scan { receipt_line_id, barcode, qty }
        def scan
          line = ReceiptLine.joins(:receipt)
                            .where(receipts: { warehouse_id: warehouse.id })
                            .find(params.require(:receipt_line_id))
          lot = ::Wms::ReceivingService.new(line, staff: current_warehouse_staff)
                                       .receive!(barcode: params.require(:barcode), qty: params.require(:qty))
          render json: { data: { lot_id: lot.id, received_qty: line.reload.received_qty,
                                 line_status: line.status, receipt_status: line.receipt.status },
                         meta: meta }
        rescue ::Wms::ReceivingService::Error => e
          render json: { error: { code: "receive_failed", message: e.message } }, status: :unprocessable_entity
        end
      end
    end
  end
end
