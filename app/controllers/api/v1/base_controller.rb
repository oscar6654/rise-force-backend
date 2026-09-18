module Api
  module V1
    # JWT-authenticated base for the mobile (React Native) API. No session/CSRF;
    # sets current_seller from a validated bearer token whose jti is not revoked.
    class BaseController < ActionController::API
      before_action :authenticate_seller!

      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActiveRecord::RecordInvalid, with: :unprocessable
      rescue_from ActionController::ParameterMissing, with: :bad_request

      attr_reader :current_seller, :current_manager, :current_role

      private

      def authenticate_seller!
        token = request.headers["Authorization"].to_s.split(" ").last
        payload = token && JsonWebToken.decode(token)
        return render_unauthorized unless payload

        device = DeviceToken.active.find_by(jti: payload[:jti])
        return render_unauthorized unless device

        @current_device = device
        @current_seller = device.seller
        @current_manager = device.manager_id ? Manager.find_by(id: device.manager_id) : nil
        @current_role = device.role.presence || "seller"
        device.update_column(:last_used_at, Time.current)
      end

      def require_manager!
        render_unauthorized unless current_role == "manager" && current_manager
      end

      # Every seller_id this login represents (login group: 1 login → 2-3 seller
      # records across branches). Falls back to just the current seller.
      def current_group_ids
        @current_group_ids ||= current_seller&.login_group_ids || []
      end

      def diser? = current_role == "diser"

      # Guard for endpoints a diser must not touch (orders, targets, coverage…).
      def deny_diser!
        render_unauthorized if diser?
      end

      def render_unauthorized
        render json: { error: { code: "unauthorized", message: "Invalid or expired token" } }, status: :unauthorized
      end

      def not_found(e)
        render json: { error: { code: "not_found", message: e.message } }, status: :not_found
      end

      def unprocessable(e)
        render json: { error: { code: "invalid", message: e.record.errors.full_messages.join(", ") } }, status: :unprocessable_entity
      end

      def bad_request(e)
        render json: { error: { code: "bad_request", message: e.message } }, status: :bad_request
      end

      def meta
        { server_time: Time.current.iso8601 }
      end

      # Delta cursor helper.
      def updated_since
        Time.zone.parse(params[:updated_since]) if params[:updated_since].present?
      rescue ArgumentError
        nil
      end

      def since_scope(relation)
        updated_since ? relation.where("updated_at > ?", updated_since) : relation
      end
    end
  end
end
