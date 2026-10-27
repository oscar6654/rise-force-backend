module Api
  module V1
    module Wms
      # Blind cycle counting on the app: list pending counts, submit a figure.
      class CountsController < BaseController
        before_action -> { require_staff_role!(:count) }

        def index
          counts = warehouse.cycle_counts.where(status: %i[pending counting])
                            .includes(:storage_location, :product).order(:created_at)
          render json: { data: counts.map { |c| count_json(c) }, meta: meta }
        end

        # POST wms/counts/:id/submit { counted_qty } — blind (no system_qty exposed)
        def submit
          count = warehouse.cycle_counts.find(params[:id])
          ::Wms::CycleCountService.new(count).submit!(counted_qty: params.require(:counted_qty),
                                                      staff: current_warehouse_staff)
          render json: { data: { id: count.id, status: count.reload.status }, meta: meta }
        end

        private

        # Deliberately omits system_qty / variance so the count stays blind.
        def count_json(c)
          { id: c.id, loc_code: c.storage_location.loc_code, zone: c.storage_location.zone,
            sku: c.product&.sku, description: c.product&.description, trigger: c.trigger, status: c.status }
        end
      end
    end
  end
end
