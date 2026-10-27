module Wms
  class CycleCountsController < ApplicationController
    before_action -> { authorize!(:cycle_count, :view) }, only: [:index, :show]
    before_action -> { authorize!(:cycle_count, :create) }, only: [:new, :create]
    before_action -> { authorize!(:cycle_count, :approve) }, only: [:reconcile]
    before_action -> { authorize!(:cycle_count, :update) }, only: [:cancel]

    def index
      scope = CycleCount.includes(:warehouse, :storage_location, :product)
      scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      @warehouses = Warehouse.wms.order(:whs_code)
      # IRA headline: accuracy = counts reconciled with zero variance / all reconciled.
      reconciled = CycleCount.where(status: :reconciled)
      @ira = reconciled.any? ? (reconciled.where(variance: 0).count * 100.0 / reconciled.count).round(1) : nil
      @counts = scope.order(created_at: :desc).page(params[:page]).per(40)
    end

    def show
      @count = CycleCount.find(params[:id])
    end

    def new
      @count = CycleCount.new(warehouse_id: params[:warehouse_id])
      @locations = location_scope
    end

    def create
      loc = StorageLocation.find(params.require(:storage_location_id))
      count = ::Wms::CycleCountService.open!(loc, trigger: :manual, reason: "console")
      redirect_to wms_cycle_count_path(count), notice: "Cycle count opened for #{loc.loc_code}."
    end

    # Reconcile a submitted count (writes the adjust movement).
    def reconcile
      count = CycleCount.find(params[:id])
      ::Wms::CycleCountService.new(count).reconcile!(user: current_user)
      redirect_to wms_cycle_count_path(count), notice: "Reconciled — stock adjusted."
    rescue ::Wms::CycleCountService::Error => e
      redirect_to wms_cycle_count_path(count), alert: e.message
    end

    def cancel
      CycleCount.find(params[:id]).update!(status: :cancelled)
      redirect_to wms_cycle_counts_path, notice: "Count cancelled."
    end

    private

    def location_scope
      s = StorageLocation.includes(:warehouse).where.not(loc_type: :receiving_dock)
      s = s.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
      s.order(:warehouse_id, :loc_code)
    end
  end
end
