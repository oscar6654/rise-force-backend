class InventoryLot < ApplicationRecord
  belongs_to :warehouse
  belongs_to :storage_location, optional: true
  belongs_to :product
  has_many :pick_allocations, dependent: :restrict_with_error

  enum :status, { received: 0, active: 1, quarantine: 2, damaged: 3, expired: 4 }, default: :received

  validates :received_date, presence: true

  # FIFO order: oldest received first, then lowest id as a stable tiebreak.
  scope :fifo, -> { order(:received_date, :id) }
  # Sellable stock lives in an active lot in a pickable location.
  scope :available, -> {
    active.joins(:storage_location)
          .where(storage_locations: { pickable: true, status: StorageLocation.statuses[:active] })
  }
  scope :for_product, ->(product) { where(product: product) }

  def qty_available
    (qty_on_hand - qty_allocated - qty_locked)
  end
end
