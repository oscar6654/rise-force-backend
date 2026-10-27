class WmsReturnLine < ApplicationRecord
  belongs_to :wms_return
  belongs_to :product, optional: true
  belongs_to :storage_location, optional: true

  enum :uom, { pc: 0, case_uom: 1 }, default: :case_uom
  enum :disposition, { saleable: 0, damaged: 1, quarantine: 2 }, prefix: :disp
  enum :status, { pending: 0, processed: 1 }, default: :pending

  # Quantity converted to canonical pieces.
  def pieces
    case_uom? ? qty * (product&.pcs_per_case || 1) : qty
  end
end
