module Api
  module V1
    module Wms
      # Confirm a physical pick against one allocation (scan location + item).
      class PicksController < BaseController
        before_action -> { require_staff_role!(:pick) }

        # POST wms/picks/:allocation_id/confirm
        #   { qty_picked, barcode, location_code, find_elsewhere }
        def confirm
          allocation = PickAllocation.joins(:fulfillment_order)
                                     .where(fulfillment_orders: { warehouse_id: warehouse.id })
                                     .find(params[:allocation_id])
          ::Wms::PickingService.new(staff: current_warehouse_staff).confirm!(
            allocation,
            qty_picked: params.require(:qty_picked),
            barcode: params[:barcode],
            location_code: params[:location_code],
            on_short: (params[:on_short].presence || "resource").to_sym
          )
          fo = allocation.fulfillment_order.reload
          render json: { data: { fulfillment_order_id: fo.id, fo_status: fo.status,
                                 allocations: fo.pick_allocations.order(:pick_sequence).map { |a|
                                   { id: a.id, status: a.status, qty_allocated: a.qty_allocated,
                                     qty_picked: a.qty_picked, loc_code: a.storage_location&.loc_code,
                                     sku: a.product&.sku } } }, meta: meta }
        rescue ::Wms::PickingService::Error => e
          render json: { error: { code: "pick_failed", message: e.message } }, status: :unprocessable_entity
        end

        # POST wms/picks/:allocation_id/undo → return a picked line to the pick list
        def undo
          allocation = PickAllocation.joins(:fulfillment_order)
                                     .where(fulfillment_orders: { warehouse_id: warehouse.id })
                                     .find(params[:allocation_id])
          ::Wms::PickingService.new(staff: current_warehouse_staff).undo!(allocation)
          fo = allocation.fulfillment_order.reload
          render json: { data: { fulfillment_order_id: fo.id, fo_status: fo.status }, meta: meta }
        rescue ::Wms::PickingService::Error => e
          render json: { error: { code: "undo_failed", message: e.message } }, status: :unprocessable_entity
        end
      end
    end
  end
end
