class ReplenishmentTask < ApplicationRecord
  belongs_to :warehouse
  belongs_to :product
  belongs_to :piece_location, class_name: "StorageLocation", optional: true
  belongs_to :fulfillment_order, optional: true
  belongs_to :assigned_to, class_name: "WarehouseStaff", optional: true

  enum :trigger, { auto: 0, manual: 1 }, default: :manual, prefix: :trigger
  enum :status, { pending: 0, assigned: 1, done: 2, cancelled: 3 }, default: :pending

  scope :open_tasks, -> { where(status: %i[pending assigned]) }

  validates :qty_cases, numericality: { greater_than: 0 }
end
