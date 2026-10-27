class FulfillmentLine < ApplicationRecord
  belongs_to :fulfillment_order
  belongs_to :product
  has_many :pick_allocations, dependent: :destroy

  enum :uom, { pc: 0, case_uom: 1 }, default: :case_uom
  enum :status, { pending: 0, allocated: 1, short: 2, picked: 3, checked: 4 }, default: :pending
  # Whether this line is picked as full cases or loose pieces (broken-case).
  enum :pack, { case: 0, loose: 1 }, default: :case, prefix: :pack

  # Demand converted to the canonical piece count (cases × pcs_per_case).
  def demanded_pieces
    case_uom? ? qty_demanded * (product.pcs_per_case || 1) : qty_demanded
  end
end
