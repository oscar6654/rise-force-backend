module Wms
  # Allocate (and assign) a fulfillment order off the request path — used by the
  # dispatch-CSV importer for large uploads. Logged under JobLog :fifo_allocation.
  class AllocateJob < ApplicationJob
    queue_as :default

    def perform(fulfillment_order_id)
      fo = FulfillmentOrder.find_by(id: fulfillment_order_id)
      return unless fo

      Wms::AllocationService.new(fo).allocate!
      Wms::PickerAssigner.new(fo).assign!
    end
  end
end
