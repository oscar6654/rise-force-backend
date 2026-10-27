module Api
  module V1
    module Wms
      # Pick jobs (fulfillment orders) assigned to the logged-in picker.
      class TasksController < BaseController
        before_action -> { require_staff_role!(:pick) }

        def index
          jobs = assigned_scope.where(status: %i[assigned picking]).order(:delivery_date, :created_at)
          render json: { data: jobs.map { |fo| job_json(fo) }, meta: meta }
        end

        def show
          fo = assigned_scope.find(params[:id])
          render json: { data: job_json(fo, detail: true), meta: meta }
        end

        # POST wms/tasks/:id/start → lock allocations, move to picking
        def start
          fo = assigned_scope.find(params[:id])
          ::Wms::PickingService.new(staff: current_warehouse_staff).start!(fo)
          render json: { data: job_json(fo.reload, detail: true), meta: meta }
        end

        # POST wms/tasks/:id/finish_short → give up on everything still open:
        # release reservations, flag bins for IRA, close the job to checking.
        def finish_short
          fo = assigned_scope.find(params[:id])
          ::Wms::PickingService.new(staff: current_warehouse_staff).finish_short!(fo)
          render json: { data: job_json(fo.reload, detail: true), meta: meta }
        end

        private

        def assigned_scope
          warehouse.fulfillment_orders.where(assigned_to_id: current_warehouse_staff.id)
        end

        def job_json(fo, detail: false)
          h = { id: fo.id, reference_no: fo.reference_no, status: fo.status, delivery_date: fo.delivery_date,
                remarks: fo.remarks, store_id: fo.store_id, line_count: fo.fulfillment_lines.size }
          if detail
            h[:allocations] = fo.pick_allocations.includes(:product, :storage_location, :inventory_lot)
                                .order(:pick_sequence).map { |a| allocation_json(a) }
            # Lines with less stock reserved than demanded = out of stock / short.
            # They have no (or partial) allocation, so they're excluded from the
            # pick list — surfaced here so the picker/checker can see "OS".
            h[:out_of_stock] = fo.fulfillment_lines.includes(:product)
                                 .select { |l| l.qty_allocated < l.qty_demanded }
                                 .map { |l| { product_id: l.product_id, sku: l.product&.sku,
                                              description: l.product&.description,
                                              pcs_per_case: l.product&.pcs_per_case || 1,
                                              demanded: l.qty_demanded, allocated: l.qty_allocated,
                                              out_of_stock: l.qty_allocated.zero? } }
          end
          h
        end

        def allocation_json(a)
          { id: a.id, status: a.status, pack: a.pack, product_id: a.product_id, sku: a.product&.sku,
            description: a.product&.description, it_barcode: a.product&.it_barcode,
            cs_barcode: a.product&.cs_barcode, pcs_per_case: a.product&.pcs_per_case || 1,
            qty_allocated: a.qty_allocated, qty_picked: a.qty_picked,
            loc_code: a.storage_location&.loc_code, lot_code: a.inventory_lot&.lot_code }
        end
      end
    end
  end
end
