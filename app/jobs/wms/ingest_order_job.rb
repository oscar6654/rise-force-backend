module Wms
  # Auto-flow: a submitted SFA order for a WMS-enabled warehouse becomes a pick
  # job. Enqueued from Order#after_commit; safe to run more than once (idempotent).
  class IngestOrderJob < ApplicationJob
    queue_as :default

    def perform(order_id)
      order = Order.find_by(id: order_id)
      return unless order && !order.cancelled?

      Wms::DemandFromOrder.new(order).call
    end
  end
end
