module Api
  module V1
    module Wms
      # Checker: verify picked jobs, then close + dispatch.
      class ChecksController < BaseController
        before_action -> { require_staff_role!(:check) }

        def index
          jobs = warehouse.fulfillment_orders.where(status: %i[picked short checking])
                          .order(:delivery_date, :created_at)
          render json: { data: jobs.map { |fo| { id: fo.id, reference_no: fo.reference_no, status: fo.status,
                                                 delivery_date: fo.delivery_date,
                                                 line_count: fo.fulfillment_lines.size } }, meta: meta }
        end

        def show
          fo = warehouse.fulfillment_orders.find(params[:id])
          render json: { data: { id: fo.id, reference_no: fo.reference_no, status: fo.status,
                                 lines: fo.fulfillment_lines.includes(:product).map { |l|
                                   { id: l.id, sku: l.product&.sku, description: l.product&.description,
                                     pcs_per_case: l.product&.pcs_per_case || 1,
                                     qty_demanded: l.qty_demanded, qty_allocated: l.qty_allocated,
                                     qty_picked: l.qty_picked, qty_checked: l.qty_checked,
                                     out_of_stock: l.qty_allocated.zero?, status: l.status } } }, meta: meta }
        end

        # POST wms/checks/:id/verify { lines: [{ line_id, qty_checked }] }
        def verify
          fo = warehouse.fulfillment_orders.find(params[:id])
          svc = ::Wms::CheckingService.new(staff: current_warehouse_staff)
          fo.update!(status: :checking) unless fo.checking?
          Array(params[:lines]).each do |lc|
            line = fo.fulfillment_lines.find(lc[:line_id])
            svc.verify!(line, qty_checked: lc[:qty_checked])
          end
          svc.complete!(fo.reload)
          ::Wms::DispatchService.new(fo.reload).dispatch! if params[:dispatch].to_s == "true" && fo.checked?
          render json: { data: { id: fo.id, status: fo.reload.status }, meta: meta }
        rescue ::Wms::DispatchService::Error => e
          render json: { error: { code: "dispatch_failed", message: e.message } }, status: :unprocessable_entity
        end
      end
    end
  end
end
