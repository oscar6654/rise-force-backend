class ReceiptLine < ApplicationRecord
  belongs_to :receipt
  belongs_to :product, optional: true

  enum :uom, { pc: 0, case_uom: 1 }, default: :case_uom
  enum :status, { pending: 0, partial: 1, received: 2, over: 3, short: 4 }, default: :pending

  # Recompute line status from received vs expected (short/over flagged, not blocked).
  def recompute_status!
    self.status =
      if received_qty <= 0 then :pending
      elsif received_qty < expected_qty then :partial
      elsif received_qty == expected_qty then :received
      else :over
      end
    save!
  end
end
