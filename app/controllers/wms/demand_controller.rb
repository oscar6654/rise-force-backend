module Wms
  # Pick jobs (fulfillment orders). Also the manual re-pull/backfill of SFA orders
  # into the WMS (safety path; the normal flow is the Order after_commit auto-flow).
  class DemandController < ApplicationController
    before_action -> { authorize!(:fulfillment_order, :view) }, only: [:index, :show]
    before_action -> { authorize!(:fulfillment_order, :update) }, only: [:allocate, :reassign, :build]

    def index
      scope = FulfillmentOrder.includes(:warehouse, :assigned_to, :store)
      scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      @warehouses = Warehouse.wms.order(:whs_code)
      @orders = scope.order(created_at: :desc).page(params[:page]).per(40)
    end

    def show
      @order = FulfillmentOrder.includes(fulfillment_lines: :product,
                                         pick_allocations: %i[storage_location inventory_lot product]).find(params[:id])
      # Pickers in this warehouse available for a manual reassignment override.
      @pickers = @order.warehouse.warehouse_staffs.active.with_role("pick").order(:name)
      @online_ids = @order.warehouse.warehouse_staffs.online.pluck(:id).to_set
    end

    # Re-run FIFO allocation + assignment for one job.
    def allocate
      fo = FulfillmentOrder.find(params[:id])
      ::Wms::AllocationService.new(fo).allocate!
      ::Wms::PickerAssigner.new(fo).assign!
      redirect_to wms_demand_path(fo), notice: "Re-allocated #{fo.reference_no}."
    end

    def reassign
      fo = FulfillmentOrder.find(params[:id])
      staff = WarehouseStaff.find(params[:warehouse_staff_id])
      fo.update!(assigned_to: staff, status: fo.pending? ? fo.status : :assigned)
      redirect_to wms_demand_path(fo), notice: "Reassigned to #{staff.name}."
    end

    # Backfill: pull not-yet-ingested submitted SFA orders for WMS warehouses.
    def build
      count = 0
      Warehouse.wms.find_each do |wh|
        Order.where(branch_id: wh.branch_id, status: :submitted).find_each do |order|
          next if FulfillmentOrder.exists?(warehouse: wh, reference_no: order.order_number)

          ::Wms::DemandFromOrder.new(order).call and count += 1
        end
      end
      redirect_to wms_demand_index_path, notice: "Pulled #{count} order(s) into the WMS."
    end
  end
end
