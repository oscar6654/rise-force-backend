module Api
  module V1
    module Wms
      # Manual stock movement (e.g. buffer → pick slot). Allowed to putaway or
      # pick staff.
      class MovesController < BaseController
        before_action :require_mover!

        # POST wms/moves { lot_id, to_location_id, qty? }
        def create
          lot = warehouse.inventory_lots.find(params.require(:lot_id))
          dest = warehouse.storage_locations.find(params.require(:to_location_id))
          moved = ::Wms::RelocationService.new(lot, staff: current_warehouse_staff)
                                          .move!(to_location: dest, qty: params[:qty].presence)
          render json: { data: { lot_id: moved.id, loc_code: moved.reload.storage_location&.loc_code,
                                 qty_on_hand: moved.qty_on_hand }, meta: meta }
        rescue ::Wms::RelocationService::Error => e
          render json: { error: { code: "move_failed", message: e.message } }, status: :unprocessable_entity
        end

        private

        def require_mover!
          ok = current_role == "staff" &&
               %w[move putaway pick].any? { |r| current_warehouse_staff&.has_role?(r) }
          render_unauthorized unless ok
        end
      end
    end
  end
end
