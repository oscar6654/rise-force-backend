require "digest"

class DeviceToken < ApplicationRecord
  belongs_to :seller, optional: true # nil for a future manager token

  validates :jti, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }

  def revoked?
    revoked_at.present?
  end

  def refresh_valid?(raw_token)
    return false if revoked? || refresh_expires_at.nil? || refresh_expires_at < Time.current

    refresh_token_digest == Digest::SHA256.hexdigest(raw_token)
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end
end
