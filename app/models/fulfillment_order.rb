class FulfillmentOrder < ApplicationRecord
  belongs_to :warehouse
  belongs_to :order, optional: true
  belongs_to :store, optional: true
  belongs_to :parent_fulfillment_order, class_name: "FulfillmentOrder", optional: true
  belongs_to :assigned_to, class_name: "WarehouseStaff", optional: true
  belongs_to :checked_by, class_name: "WarehouseStaff", optional: true
  has_many :child_fulfillment_orders, class_name: "FulfillmentOrder",
           foreign_key: :parent_fulfillment_order_id, dependent: :nullify
  has_many :fulfillment_lines, dependent: :destroy
  has_many :pick_allocations, dependent: :destroy

  enum :source, { sfa_order: 0, dispatch_csv: 1 }, default: :sfa_order
  enum :status, {
    pending: 0, allocated: 1, assigned: 2, picking: 3, picked: 4,
    checking: 5, checked: 6, short: 7, dispatched: 8, cancelled: 9
  }, default: :pending

  validates :reference_no, presence: true, uniqueness: { scope: :warehouse_id }

  scope :open_jobs, -> { where.not(status: %i[dispatched cancelled]) }
  scope :unassigned, -> { where(assigned_to_id: nil).where.not(status: %i[dispatched cancelled]) }

  # Distinct brand ids across this job's lines (for brand_per_picker routing).
  def brand_ids
    Product.where(id: fulfillment_lines.select(:product_id)).distinct.pluck(:brand_id).compact
  end
end
