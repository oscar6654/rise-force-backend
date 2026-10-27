class Receipt < ApplicationRecord
  belongs_to :warehouse
  has_many :receipt_lines, dependent: :destroy

  enum :source, { upload: 0 }, default: :upload
  enum :status, { open: 0, receiving: 1, received: 2, closed: 3 }, default: :open

  validates :po_ref, presence: true, uniqueness: { scope: :warehouse_id, case_sensitive: false }

  # Fully matched when every line has been received to (or past) its expected qty.
  def fully_received?
    receipt_lines.any? && receipt_lines.all? { |l| l.received? || l.over? }
  end
end
