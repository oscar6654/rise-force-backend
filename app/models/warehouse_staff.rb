class WarehouseStaff < ApplicationRecord
  # Separate mobile account (not a seller): logs into Rise Force with staff_code +
  # PIN. Blank PIN falls back to the shared mobile PIN, same as diser/seller.
  has_secure_password :pin, validations: false

  belongs_to :warehouse
  belongs_to :seller, optional: true

  # A staff member can hold several roles at once (receive, putaway, pick, check,
  # count, move). Stored as a Postgres string array.
  ROLES = %w[receive putaway pick pick_pieces check count move replenish returns].freeze

  enum :status, { active: 0, inactive: 1 }, default: :active

  has_many :device_tokens, dependent: :nullify

  # Default window (minutes) within which a staff's app activity counts as
  # "online" for auto-assignment. Overridable via SystemSetting.
  PRESENCE_WINDOW_MIN = 30

  validates :staff_code, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  validate  :roles_are_known
  validate  :staff_code_not_a_seller_or_diser_or_manager_code

  normalizes :roles, with: ->(v) { Array(v).map { |r| r.to_s.strip.downcase }.reject(&:blank?).uniq }
  normalizes :zones, with: ->(v) { Array(v).map { |z| z.to_s.strip }.reject(&:blank?).uniq }

  # `active` scope comes from the status enum.
  scope :with_role, ->(role) { where("? = ANY(roles)", role.to_s) }
  # "Online" = an active staff with a live (non-revoked) device token used within
  # the presence window — i.e. logged into the app and recently alive. Only these
  # are auto-assigned pick jobs (an absent picker never gets work).
  scope :online, ->(window = presence_window) {
    active.where(id: DeviceToken.active.where.not(warehouse_staff_id: nil)
                                .where("last_used_at > ?", window.ago).select(:warehouse_staff_id))
  }

  def self.presence_window
    SystemSetting.get("wms_picker_presence_minutes", PRESENCE_WINDOW_MIN).to_i.minutes
  end

  # Whether this staff is currently online (for console presence badges).
  def online?
    device_tokens.active.where("last_used_at > ?", self.class.presence_window.ago).exists?
  end

  def has_role?(role)
    roles.include?(role.to_s)
  end

  def pin_set?
    pin_digest.present?
  end

  private

  def roles_are_known
    bad = Array(roles) - ROLES
    errors.add(:roles, "unknown: #{bad.join(', ')}") if bad.any?
  end

  # A staff code must not collide with any seller/diser/manager login code —
  # otherwise the shared login endpoint would resolve to the wrong identity.
  def staff_code_not_a_seller_or_diser_or_manager_code
    return if staff_code.blank?

    code = staff_code.downcase
    clash = Seller.where("lower(seller_code) = ? OR lower(diser_code) = ?", code, code).exists? ||
            Manager.where("lower(code) = ?", code).exists?
    errors.add(:staff_code, "must be different from every seller, diser and manager code") if clash
  end
end
