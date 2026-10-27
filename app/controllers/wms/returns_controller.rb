module Wms
  # Returns & quality. Upload a returns CSV (like the ASN), then process each line:
  # tag it saleable / damaged / quarantine and the system suggests where to drop
  # it (saleable → stock/piece zone; damaged/quarantine → damage zone). The ad-hoc
  # single-return form stays available too.
  class ReturnsController < ApplicationController
    before_action -> { authorize!(:wms_return, :view) }, only: [:index, :show]
    before_action -> { authorize!(:wms_return, :create) }, only: [:new, :create]
    before_action -> { authorize!(:wms_return, :update) }, only: [:process_line]

    DISP_MOVES = %i[return_in damage quarantine release writeoff].freeze

    def index
      scope = WmsReturn.includes(:warehouse, :store).where(status: %i[open processing])
      scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
      @warehouses = Warehouse.order(:whs_code)
      @returns = scope.order(created_at: :desc).page(params[:page]).per(30)
      @recent = StockMovement.includes(:warehouse, :product, :storage_location)
                             .where(movement_type: DISP_MOVES).recent.limit(15)
    end

    def show
      @return = WmsReturn.includes(wms_return_lines: %i[product storage_location]).find(params[:id])
      # Pre-compute the suggested drop location for each disposition, per line.
      @suggestions = {}
      @return.wms_return_lines.each do |l|
        next unless l.product

        @suggestions[l.id] = %w[saleable damaged quarantine].index_with do |d|
          ::Wms::ReturnService.suggest_location(@return.warehouse, l.product, d, loose: l.pc?)&.loc_code
        end
      end
    end

    # Process one return line: apply the chosen disposition at the suggested (or
    # overridden) location.
    def process_line
      ret = WmsReturn.find(params[:id])
      line = ret.wms_return_lines.find(params.require(:line_id))
      disposition = params.require(:disposition)
      loc = if params[:location_id].present?
              ret.warehouse.storage_locations.find(params[:location_id])
            else
              ::Wms::ReturnService.suggest_location(ret.warehouse, line.product, disposition, loose: line.pc?)
            end
      raise ActiveRecord::RecordInvalid unless loc && line.product

      ::Wms::ReturnService.new(ret.warehouse, user: current_user)
                          .record!(product: line.product, qty: line.pieces, disposition: disposition,
                                   location: loc, reason: "return #{ret.ref}")
      line.update!(disposition: disposition, status: :processed, storage_location: loc)
      ret.refresh_status!
      redirect_to wms_return_path(ret), notice: "#{line.product.sku}: #{disposition} → #{loc.loc_code}."
    rescue ::Wms::ReturnService::Error, ActiveRecord::RecordInvalid => e
      redirect_to wms_return_path(params[:id]), alert: "Could not process: #{e.message}"
    end

    # ---- ad-hoc single return (unchanged) ----
    def new
      @warehouses = Warehouse.order(:whs_code)
    end

    def create
      wh = Warehouse.find(params.require(:warehouse_id))
      product = Product.find(params.require(:product_id))
      location = wh.storage_locations.find(params.require(:location_id))
      ::Wms::ReturnService.new(wh, user: current_user).record!(
        product: product, qty: params.require(:qty), disposition: params.require(:disposition),
        location: location, reason: params[:reason]
      )
      redirect_to wms_returns_path, notice: "Return recorded (#{params[:disposition]})."
    rescue ::Wms::ReturnService::Error => e
      redirect_to new_wms_return_path, alert: e.message
    end
  end
end
