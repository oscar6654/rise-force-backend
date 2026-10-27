module Wms
  class ReceiptsController < ApplicationController
    before_action -> { authorize!(:receipt, :view) }

    def index
      scope = Receipt.includes(:warehouse)
      scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
      @warehouses = Warehouse.order(:whs_code)
      @receipts = scope.order(created_at: :desc).page(params[:page]).per(40)
    end

    def show
      @receipt = Receipt.includes(receipt_lines: :product).find(params[:id])
    end
  end
end
