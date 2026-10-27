class CycleCount < ApplicationRecord
  belongs_to :warehouse
  belongs_to :storage_location
  belongs_to :product, optional: true
  belongs_to :inventory_lot, optional: true
  belongs_to :counted_by, class_name: "WarehouseStaff", optional: true
  belongs_to :reconciled_by, class_name: "User", optional: true

  enum :trigger, { scheduled: 0, random: 1, manual: 2, pick_discrepancy: 3 }, default: :manual
  enum :status, { pending: 0, counting: 1, counted: 2, reconciled: 3, cancelled: 4 }, default: :pending

  scope :open_counts, -> { where(status: %i[pending counting counted]) }

  def discrepancy?
    variance.present? && !variance.zero?
  end
end
