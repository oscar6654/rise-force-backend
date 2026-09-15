module Api
  module V1
    class VisitsController < BaseController
      # POST /api/v1/visits/checkin
      # { client_uuid, store_id, route_id?, checkin_lat, checkin_lng, started_at, planned_visit_id? }
      def checkin
        uuid = params.require(:client_uuid)
        visit = Visit.find_by(client_uuid: uuid)
        return render(json: { data: visit_json(visit), meta: meta }) if visit

        store = Store.find(params.require(:store_id))
        distance = gps_distance(store, params[:checkin_lat], params[:checkin_lng])

        # Anti-fraud geofence (backend-configurable). hard = block beyond radius;
        # soft = allow but demand a reason; warn = just record.
        if (msg = geofence_violation(distance))
          return render(json: { error: { code: "geofence", message: msg, distance_m: distance } },
                        status: :unprocessable_entity)
        end

        visit = Visit.create!(
          client_uuid: uuid, seller: current_seller, store: store, route: store.route,
          status: :in_progress, started_at: params[:started_at] || Time.current,
          checkin_lat: params[:checkin_lat], checkin_lng: params[:checkin_lng],
          gps_mismatch_distance_m: distance,
          geofence_reason: params[:geofence_reason].presence,
          off_route: !on_todays_plan?(store)
        )
        render json: { data: visit_json(visit), meta: meta }, status: :created
      end

      # POST /api/v1/visits/:client_uuid/checkout
      # { checkout_lat, checkout_lng, ended_at, status, no_order_reason? }
      def checkout
        visit = Visit.find_by!(client_uuid: params[:client_uuid], seller: current_seller)
        visit.update!(
          checkout_lat: params[:checkout_lat], checkout_lng: params[:checkout_lng],
          ended_at: params[:ended_at] || Time.current,
          status: params[:status].presence || (visit.order ? :closed_with_order : :closed_no_order),
          no_order_reason: params[:no_order_reason]
        )
        render json: { data: visit_json(visit), meta: meta }
      end

      def index
        rows = since_scope(Visit.where(seller: current_seller)).order(started_at: :desc).limit(200).map { |v| visit_json(v) }
        render json: { data: rows, meta: meta }
      end

      private

      def on_todays_plan?(store)
        store.route&.seller_id == current_seller.id && store.due_on?(Date.current)
      end

      def gps_distance(store, lat, lng)
        return nil if store.latitude.blank? || lat.blank?

        StoreDuplicateDetector.distance_m(store.latitude.to_f, store.longitude.to_f, lat.to_f, lng.to_f).round
      rescue StandardError
        nil
      end

      # nil = ok. Backend-configurable: hard blocks, soft needs a reason, warn allows.
      def geofence_violation(distance)
        return nil if distance.nil? # no GPS / no store pin -> nothing to enforce

        radius = SystemSetting.get("checkin_geofence_radius_m", 150).to_i
        return nil if distance <= radius

        case SystemSetting.get("checkin_geofence_mode", "soft").to_s
        when "hard"
          "You are #{distance} m from the store — too far to check in (max #{radius} m)."
        when "soft"
          params[:geofence_reason].present? ? nil : "You are #{distance} m from the store. Add a reason to check in this far away."
        else
          nil # warn: allowed
        end
      end

      def visit_json(v)
        { id: v.id, client_uuid: v.client_uuid, store_id: v.store_id, status: v.status,
          off_route: v.off_route, gps_mismatch_distance_m: v.gps_mismatch_distance_m,
          started_at: v.started_at, ended_at: v.ended_at }
      end
    end
  end
end
