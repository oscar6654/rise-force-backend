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
  # Orders currently owned by the WMS and NOT yet available for OSB batch
  # download: the seller is WMS-routed (seller + warehouse both wms_enabled) and
  # the order is not fully dispatched — i.e. it has no fulfillment order yet, OR
  # at least one of its fulfillment orders (a split job may have several) is still
  # open. Only once EVERY FO is dispatched does the order leave this scope and
  # become batchable with the final shipped quantities.
  scope :wms_held, -> {
    undispatched = FulfillmentOrder.where.not(status: %i[dispatched cancelled]).select(:order_id)
    with_any_fo  = FulfillmentOrder.select(:order_id)
    joins(seller: :warehouse)
      .where(sellers: { wms_enabled: true }, warehouses: { wms_enabled: true })
      .where("orders.id IN (#{undispatched.to_sql}) OR orders.id NOT IN (#{with_any_fo.to_sql})")
  }
  scope :batchable_pending, -> { unbatched.where.not(id: wms_held.select(:id)) }

  before_create :assign_order_number
  # Auto-flow to the WMS: a new order for a WMS-enabled branch becomes a pick job.
  # No-ops (in the job) when the branch has no WMS warehouse, so non-WMS
  # deployments are unaffected.
  after_commit :enqueue_wms_ingest, on: :create

  def recompute_total!
    update!(total_amount: order_lines.sum(:line_total))
  end

  private

  def enqueue_wms_ingest
    return if cancelled?
    # Only when this order's seller is WMS-routed (seller + its warehouse both
    # wms_enabled). Everyone else stays on the OSB batch-download path.
    return unless seller&.wms_order_routing?

    Wms::IngestOrderJob.perform_later(id)
  end

  def assign_order_number
    self.order_number ||= "SO-#{ordered_at&.strftime('%Y%m%d') || Time.current.strftime('%Y%m%d')}-#{SecureRandom.hex(3).upcase}"
  end
end
