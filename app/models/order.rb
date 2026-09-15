class Order < ApplicationRecord
  belongs_to :seller
  belongs_to :store
  belongs_to :branch
  belongs_to :route, optional: true
  belongs_to :order_batch, optional: true
  belongs_to :pricing_version, optional: true
  belongs_to :visit, optional: true
  has_many :order_lines, dependent: :destroy

  enum :status, { submitted: 0, batched: 1, downloaded: 2, invoiced: 3, cancelled: 4 }, default: :submitted

  validates :client_uuid, presence: true, uniqueness: true

  scope :for_branches, ->(ids) { where(branch_id: ids) }
  scope :unbatched, -> { where(order_batch_id: nil, status: :submitted) }

  before_create :assign_order_number

  def recompute_total!
    update!(total_amount: order_lines.sum(:line_total))
  end

  private

  def assign_order_number
    self.order_number ||= "SO-#{ordered_at&.strftime('%Y%m%d') || Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(3).upcase}"
  end
end
