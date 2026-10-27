class Warehouse < ApplicationRecord
  belongs_to :branch, optional: true

  has_many :storage_locations, dependent: :destroy
  has_many :inventory_lots, dependent: :destroy
  has_many :warehouse_staffs, dependent: :destroy
  has_many :receipts, dependent: :destroy
  has_many :fulfillment_orders, dependent: :destroy
  has_many :cycle_counts, dependent: :destroy
  has_many :stock_movements, dependent: :destroy
  has_many :replenishment_tasks, dependent: :destroy
  has_many :wms_returns, dependent: :destroy

  enum :status, { active: 0, inactive: 1 }, default: :active
  # How picker ownership is decided for this warehouse's pick jobs.
  enum :allocation_strategy, { brand_per_picker: 0, zone_per_picker: 1 }, default: :brand_per_picker

  validates :whs_code, presence: true, uniqueness: { case_sensitive: false }
  validates :wh_name, presence: true

  scope :wms, -> { where(wms_enabled: true) }

  # Where new receipts land before putaway (one dock location per warehouse).
  def receiving_dock
    storage_locations.find_by(loc_type: :receiving_dock)
  end
end
