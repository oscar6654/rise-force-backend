require "jwt"

# Encodes/decodes short-lived access tokens for the mobile API. Carries the
# seller id + a jti (matched against DeviceToken for revocation).
module JsonWebToken
  ALGO = "HS256".freeze
  ACCESS_TTL = 30.minutes

  def self.secret
    Rails.application.secret_key_base
  end

  def self.encode(payload, exp: ACCESS_TTL.from_now)
    JWT.encode(payload.merge(exp: exp.to_i), secret, ALGO)
  end

  def self.decode(token)
    body = JWT.decode(token, secret, true, algorithm: ALGO).first
    body.deep_symbolize_keys
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end
end
