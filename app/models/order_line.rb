class OrderLine < ApplicationRecord
  belongs_to :order
  belongs_to :product
  belongs_to :promo, optional: true

  enum :line_type, { sale: 0, promo_free_good: 1 }, prefix: :line
  enum :uom, { pc: 0, case_uom: 1 }, prefix: :uom

  before_save :compute_line_total

  private

  def compute_line_total
    self.line_total = (unit_price * quantity) - line_discount
  end
end
