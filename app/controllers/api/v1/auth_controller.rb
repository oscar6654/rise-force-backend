module Api
  module V1
    class AuthController < BaseController
      skip_before_action :authenticate_seller!, only: [:login, :refresh]

      REFRESH_TTL = 30.days

      # POST /api/v1/auth/login  { seller_code, pin, device_id, platform, app_version }
      # For phase-1 the seller "pin" is validated against a SystemSetting shared
      # PIN or the seller_code itself; real per-seller credentials come later.
      def login
        seller = Seller.active.find_by(seller_code: params[:seller_code])
        return render_unauthorized unless seller && valid_pin?(seller, params[:pin])

        tokens = issue_tokens(seller, **device_params)
        render json: { data: tokens.merge(seller: seller_json(seller)), meta: meta }
      end

      # POST /api/v1/auth/refresh { refresh_token, device_id }
      def refresh
        device = DeviceToken.active.find_by(device_id: params[:device_id])
        return render_unauthorized unless device&.refresh_valid?(params[:refresh_token].to_s)

        device.update!(revoked_at: Time.current) # rotate: revoke old jti
        tokens = issue_tokens(device.seller, device_id: device.device_id,
                              platform: device.platform, app_version: device.app_version)
        render json: { data: tokens, meta: meta }
      end

      # DELETE /api/v1/auth/logout
      def logout
        @current_device&.update(revoked_at: Time.current)
        render json: { data: { ok: true }, meta: meta }
      end

      private

      def device_params
        { device_id: params[:device_id], platform: params[:platform], app_version: params[:app_version] }
      end

      # Per-seller PIN if one is set on the seller master; otherwise the shared
      # fallback PIN (so sellers without a PIN yet can still sign in).
      def valid_pin?(seller, pin)
        return seller.authenticate_pin(pin.to_s).present? if seller.pin_set?

        pin.to_s == SystemSetting.get("mobile_shared_pin", "1234").to_s
      end

      def issue_tokens(seller, device_id:, platform: nil, app_version: nil)
        jti = SecureRandom.uuid
        raw_refresh = SecureRandom.hex(32)
        DeviceToken.create!(
          seller: seller, device_id: device_id, jti: jti,
          refresh_token_digest: DeviceToken.digest(raw_refresh),
          refresh_expires_at: REFRESH_TTL.from_now,
          platform: platform, app_version: app_version, last_used_at: Time.current
        )
        seller.update_column(:last_sync_at, Time.current)
        {
          access_token: JsonWebToken.encode({ seller_id: seller.id, jti: jti }),
          refresh_token: raw_refresh,
          expires_in: JsonWebToken::ACCESS_TTL.to_i
        }
      end

      def seller_json(seller)
        { id: seller.id, code: seller.seller_code, name: seller.name, branch_id: seller.branch_id }
      end
    end
  end
end
