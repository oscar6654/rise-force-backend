module Wms
  # Replenishment: break full cases into loose pieces in the piece-pick zone.
  # Auto tasks are raised by allocation; a replenisher executes them here, or
  # runs a manual case→pieces drop.
  class ReplenishmentsController < ApplicationController
    before_action -> { authorize!(:replenishment, :view) }, only: [:index]
    before_action -> { authorize!(:replenishment, :create) }, only: [:new, :create, :execute]
    before_action -> { authorize!(:replenishment, :update) }, only: [:cancel]

    def index
      scope = ReplenishmentTask.includes(:warehouse, :product, :piece_location)
      scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      @warehouses = Warehouse.wms.order(:whs_code)
      @tasks = scope.order(created_at: :desc).page(params[:page]).per(40)
    end

    def new
      @warehouses = Warehouse.where.not(piece_pick_zone: [nil, ""]).order(:whs_code)
    end

    # Manual case → pieces drop.
    def create
      wh = Warehouse.find(params.require(:warehouse_id))
      product = Product.find(params.require(:product_id))
      from = params[:from_location_id].present? ? wh.storage_locations.find(params[:from_location_id]) : nil
      moved = ::Wms::ReplenishmentService.new(wh, user: current_user)
                                         .manual!(product: product, qty_cases: params.require(:qty_cases), from_location: from)
      redirect_to wms_replenishments_path, notice: "Dropped #{moved.to_i} pc to the piece zone."
    rescue ::Wms::ReplenishmentService::Error => e
      redirect_to new_wms_replenishment_path, alert: e.message
    end

    def execute
      task = ReplenishmentTask.find(params[:id])
      ::Wms::ReplenishmentService.new(task.warehouse, user: current_user).execute!(task)
      redirect_to wms_replenishments_path, notice: "Replenished #{task.pieces.to_i} pc for #{task.product.sku}."
    rescue ::Wms::ReplenishmentService::Error => e
      redirect_to wms_replenishments_path, alert: e.message
    end

    def cancel
      ReplenishmentTask.find(params[:id]).update!(status: :cancelled)
      redirect_to wms_replenishments_path, notice: "Task cancelled."
    end
  end
end
