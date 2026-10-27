module Wms
  class StockMovementsController < ApplicationController
    before_action -> { authorize!(:stock_movement, :view) }

    def index
      @warehouses = Warehouse.order(:whs_code)
      @movements = StockMovement.filtered(params)
                               .includes(:warehouse, :product, :storage_location, :warehouse_staff, :user)
                               .recent.page(params[:page]).per(60)
    end
  end
end
