class PickAllocation < ApplicationRecord
  belongs_to :fulfillment_line
  belongs_to :fulfillment_order
  belongs_to :inventory_lot, optional: true
  belongs_to :storage_location, optional: true
  belongs_to :product

  enum :status, { allocated: 0, locked: 1, picked: 2, partial: 3, short: 4, cancelled: 5 }, default: :allocated
  enum :pack, { case: 0, loose: 1 }, default: :case, prefix: :pack

  scope :open_for_pick, -> { where(status: %i[allocated locked]) }

  def qty_outstanding
    qty_allocated - qty_picked
  end
end
