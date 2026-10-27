module Api
  module V1
    module Wms
      # Lots waiting at the receiving dock, their suggested destination, and the
      # confirm (scan-to-location) action.
      class PutawayController < BaseController
        before_action -> { require_staff_role!(:putaway) }

        # GET wms/putaway/pending → received lots still on the dock
        def pending
          lots = warehouse.inventory_lots.where(status: :received).includes(:product, :storage_location)
          render json: { data: lots.map { |l| lot_json(l) }, meta: meta }
        end

        # GET wms/putaway/:lot_id/suggest
        def suggest
          lot = warehouse.inventory_lots.find(params[:lot_id])
          svc = ::Wms::PutawayService.new(lot, staff: current_warehouse_staff)
          render json: { data: { suggested: location_json(svc.suggest),
                                 candidates: svc.candidates.first(10).map { |l| location_json(l) } }, meta: meta }
        end

        # POST wms/putaway/:lot_id/confirm { location_id, qty? }
        def confirm
          lot = warehouse.inventory_lots.find(params[:lot_id])
          location = warehouse.storage_locations.find(params.require(:location_id))
          dest = ::Wms::PutawayService.new(lot, staff: current_warehouse_staff)
                                      .putaway!(location: location, qty: params[:qty].presence)
          render json: { data: lot_json(dest.reload), meta: meta }
        rescue ::Wms::PutawayService::Error => e
          render json: { error: { code: "putaway_failed", message: e.message } }, status: :unprocessable_entity
        end

        private

        def lot_json(lot)
          { id: lot.id, product_id: lot.product_id, sku: lot.product&.sku, description: lot.product&.description,
            it_barcode: lot.product&.it_barcode, lot_code: lot.lot_code, received_date: lot.received_date,
            qty_on_hand: lot.qty_on_hand, status: lot.status, location: location_json(lot.storage_location) }
        end

        def location_json(loc)
          return nil unless loc

          { id: loc.id, loc_code: loc.loc_code, zone: loc.zone, loc_type: loc.loc_type }
        end
      end
    end
  end
end
