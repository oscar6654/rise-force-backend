module Api
  module V1
    module Wms
      # Replenishment on the app (replenish role): list tasks, execute one, or do
      # a manual case→pieces drop.
      class ReplenishmentsController < BaseController
        before_action -> { require_staff_role!(:replenish) }

        def index
          tasks = warehouse.replenishment_tasks.open_tasks.includes(:product, :piece_location).order(:created_at)
          render json: { data: tasks.map { |t| task_json(t) }, meta: meta }
        end

        # POST wms/replenishments/:id/execute
        def execute
          task = warehouse.replenishment_tasks.find(params[:id])
          pieces = ::Wms::ReplenishmentService.new(warehouse, staff: current_warehouse_staff).execute!(task)
          render json: { data: { id: task.id, status: task.reload.status, pieces: pieces }, meta: meta }
        rescue ::Wms::ReplenishmentService::Error => e
          render json: { error: { code: "replenish_failed", message: e.message } }, status: :unprocessable_entity
        end

        # POST wms/replenishments/manual { product_id, qty_cases, from_location_id, to_location_id }
        def manual
          product = Product.find(params.require(:product_id))
          from = params[:from_location_id].present? ? warehouse.storage_locations.find(params[:from_location_id]) : nil
          dest = params[:to_location_id].present? ? warehouse.storage_locations.find(params[:to_location_id]) : nil
          pieces = ::Wms::ReplenishmentService.new(warehouse, staff: current_warehouse_staff)
                                              .manual!(product: product, qty_cases: params.require(:qty_cases),
                                                       from_location: from, piece_location: dest)
          render json: { data: { product_id: product.id, pieces: pieces }, meta: meta }
        rescue ::Wms::ReplenishmentService::Error => e
          render json: { error: { code: "replenish_failed", message: e.message } }, status: :unprocessable_entity
        end

        private

        def task_json(t)
          # The FIFO case bins to pull from — guides the worker to the right place.
          sources = ::Wms::ReplenishmentService.new(warehouse).fifo_sources(t.product, t.pieces)
          { id: t.id, product_id: t.product_id, sku: t.product&.sku, description: t.product&.description,
            pcs_per_case: t.product&.pcs_per_case || 1, qty_cases: t.qty_cases, pieces: t.pieces,
            piece_loc: t.piece_location&.loc_code, trigger: t.trigger, status: t.status,
            sources: sources.map { |s| { loc_code: s[:loc_code], lot_code: s[:lot_code], take: s[:take] } } }
        end
      end
    end
  end
end
