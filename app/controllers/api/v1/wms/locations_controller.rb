module Api
  module V1
    module Wms
      # Resolve a scanned location code to its details + current contents.
      class LocationsController < BaseController
        # GET wms/locations/lookup?loc_code=A-01-01
        def lookup
          loc = warehouse.storage_locations.find_by("lower(loc_code) = ?", params.require(:loc_code).to_s.strip.downcase)
          return render(json: { error: { code: "not_found", message: "Unknown location" } }, status: :not_found) unless loc

          lots = loc.inventory_lots.where("qty_on_hand > 0").includes(:product)
          render json: { data: {
            id: loc.id, loc_code: loc.loc_code, zone: loc.zone, loc_type: loc.loc_type,
            pickable: loc.pickable, slot_capacity: loc.slot_capacity, occupied_slots: loc.occupied_slots,
            lots: lots.map { |l| { lot_id: l.id, sku: l.product&.sku, qty_on_hand: l.qty_on_hand,
                                   lot_code: l.lot_code } }
          }, meta: meta }
        end
      end
    end
  end
end
