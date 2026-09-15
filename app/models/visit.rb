class Visit < ApplicationRecord
  belongs_to :seller
  belongs_to :store
  belongs_to :route, optional: true
  has_many :stock_counts, dependent: :destroy
  has_many :competitor_price_checks, dependent: :destroy
  has_many :visit_photos, dependent: :destroy
  has_one :order, dependent: :nullify

  enum :status, { planned: 0, in_progress: 1, closed_with_order: 2, closed_no_order: 3 }, default: :planned

  validates :client_uuid, presence: true, uniqueness: true
  validates :no_order_reason, presence: true, if: :closed_no_order?

  before_validation :set_visit_date, on: :create

  scope :for_branches, ->(ids) { joins(:store).where(stores: { branch_id: ids }) }
  scope :with_geofence_override, -> { where.not(geofence_reason: [nil, ""]) }
  scope :beyond_radius, ->(m) { where("gps_mismatch_distance_m > ?", m.to_i) }

  # The seller checked in outside the geofence and had to give a reason (soft mode).
  def geofence_override?
    geofence_reason.present?
  end

  private

  def set_visit_date
    self.visit_date ||= (started_at || Time.current).to_date
  end
end
