module Api
  module V1
    class AuthController < BaseController
      skip_before_action :authenticate_seller!, only: [:login, :refresh]

      REFRESH_TTL = 30.days

      # POST /api/v1/auth/login  { seller_code, pin, device_id, platform, app_version }
      # For phase-1 the seller "pin" is validated against a SystemSetting shared
      # PIN or the seller_code itself; real per-seller credentials come later.
      def login
        code = params[:seller_code].to_s
        pin  = params[:pin].to_s

        if (pair = resolve_identity(code, pin))
          seller, role = pair
          tokens = issue_tokens(seller, role: role, **device_params)
          return render json: { data: tokens.merge(role: role, seller: seller_json(seller, role)), meta: meta }
        end

        if (m = Manager.active.find_by("lower(code) = ?", code.downcase)) && valid_manager_pin?(m, pin)
          tokens = issue_manager_tokens(m, **device_params)
          return render json: { data: tokens.merge(role: "manager", manager: manager_json(m)), meta: meta }
        end

        render_unauthorized
      end

      # POST /api/v1/auth/refresh { refresh_token, device_id }
      def refresh
        device = DeviceToken.active.find_by(device_id: params[:device_id])
        return render_unauthorized unless device&.refresh_valid?(params[:refresh_token].to_s)

        device.update!(revoked_at: Time.current) # rotate: revoke old jti
        tokens =
          if device.role == "manager" && device.manager_id
            issue_manager_tokens(Manager.find(device.manager_id), device_id: device.device_id,
                                 platform: device.platform, app_version: device.app_version)
          else
            issue_tokens(device.seller, role: device.role, device_id: device.device_id,
                         platform: device.platform, app_version: device.app_version)
          end
        render json: { data: tokens.merge(role: device.role), meta: meta }
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

      # The same login field accepts a seller_code (full access) OR a diser_code
      # (stock-check only) — resolve which, and validate its PIN.
      def resolve_identity(code, pin)
        if (s = Seller.active.find_by(seller_code: code)) && valid_pin?(s, pin)
          return [s, "seller"]
        end
        if (s = Seller.active.find_by(diser_code: code)) && valid_diser_pin?(s, pin)
          return [s, "diser"]
        end

        nil
      end

      # Per-seller PIN if one is set on the seller master; otherwise the shared
      # fallback PIN (so sellers without a PIN yet can still sign in).
      def valid_pin?(seller, pin)
        return seller.authenticate_pin(pin.to_s).present? if seller.pin_set?

        pin.to_s == SystemSetting.get("mobile_shared_pin", "1234").to_s
      end

      def valid_diser_pin?(seller, pin)
        return seller.authenticate_diser_pin(pin.to_s).present? if seller.diser_pin_set?

        pin.to_s == SystemSetting.get("mobile_shared_pin", "1234").to_s
      end

      def valid_manager_pin?(manager, pin)
        return manager.authenticate_pin(pin.to_s).present? if manager.pin_set?

        pin.to_s == SystemSetting.get("mobile_shared_pin", "1234").to_s
      end

      def issue_manager_tokens(manager, device_id:, platform: nil, app_version: nil)
        jti = SecureRandom.uuid
        raw_refresh = SecureRandom.hex(32)
        DeviceToken.create!(
          manager_id: manager.id, role: "manager", device_id: device_id, jti: jti,
          refresh_token_digest: DeviceToken.digest(raw_refresh),
          refresh_expires_at: REFRESH_TTL.from_now,
          platform: platform, app_version: app_version, last_used_at: Time.current
        )
        {
          access_token: JsonWebToken.encode({ manager_id: manager.id, jti: jti, role: "manager" }),
          refresh_token: raw_refresh,
          expires_in: JsonWebToken::ACCESS_TTL.to_i
        }
      end

      def manager_json(manager)
        { id: manager.id, code: manager.code, name: manager.name, branch_id: manager.branch_id, role: "manager" }
      end

      def issue_tokens(seller, device_id:, role: "seller", platform: nil, app_version: nil)
        jti = SecureRandom.uuid
        raw_refresh = SecureRandom.hex(32)
        DeviceToken.create!(
          seller: seller, role: role, device_id: device_id, jti: jti,
          refresh_token_digest: DeviceToken.digest(raw_refresh),
          refresh_expires_at: REFRESH_TTL.from_now,
          platform: platform, app_version: app_version, last_used_at: Time.current
        )
        seller.update_column(:last_sync_at, Time.current)
        {
          access_token: JsonWebToken.encode({ seller_id: seller.id, jti: jti, role: role }),
          refresh_token: raw_refresh,
          expires_in: JsonWebToken::ACCESS_TTL.to_i
        }
      end

      def seller_json(seller, role = "seller")
        { id: seller.id, code: (role == "diser" ? seller.diser_code : seller.seller_code),
          name: (role == "diser" ? (seller.diser_name.presence || seller.name) : seller.name),
          branch_id: seller.branch_id, role: role }
      end
    end
  end
end
