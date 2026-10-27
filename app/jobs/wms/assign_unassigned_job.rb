module Wms
  # When a picker logs into the app, sweep the warehouse's unassigned pick jobs
  # and (re)run assignment — so work queued while nobody was online gets handed
  # to whoever is now present. Skips consolidation shells (split parents).
  class AssignUnassignedJob < ApplicationJob
    queue_as :default

    def perform(warehouse_id)
      return unless warehouse_id

      FulfillmentOrder.where(warehouse_id: warehouse_id, assigned_to_id: nil, status: %i[allocated short])
                      .where(parent_fulfillment_order_id: nil)
                      .find_each { |fo| Wms::PickerAssigner.new(fo).assign! }
    end
  end
end
