module Api
  module V1
    module Wms
      # Returns & quality on the app (returns role): list pending return lines,
      # tag each saleable/damaged/quarantine, and the system suggests the drop
      # location (saleable → stock/piece zone; damaged/quarantine → damage zone).
      class ReturnsController < BaseController
        before_action -> { require_staff_role!(:returns) }

        def index
          lines = WmsReturnLine.joins(:wms_return)
                               .where(wms_returns: { warehouse_id: warehouse.id }, status: :pending)
                               .includes(:product, wms_return: :store).order("wms_returns.created_at")
          render json: { data: lines.map { |l| line_json(l) }, meta: meta }
        end

        # POST wms/returns/:line_id/process { disposition, location_code? }
        def process_line
          line = WmsReturnLine.joins(:wms_return)
                              .where(wms_returns: { warehouse_id: warehouse.id }).find(params[:line_id])
          disposition = params.require(:disposition)
          loc = if params[:location_code].present?
                  warehouse.storage_locations.find_by!("lower(loc_code) = ?", params[:location_code].to_s.downcase)
                else
                  ::Wms::ReturnService.suggest_location(warehouse, line.product, disposition, loose: line.pc?)
                end
          raise ::Wms::ReturnService::Error, "No location available for #{disposition}" unless loc && line.product

          ::Wms::ReturnService.new(warehouse, staff: current_warehouse_staff)
                              .record!(product: line.product, qty: line.pieces, disposition: disposition,
                                       location: loc, reason: "return #{line.wms_return.ref}")
          line.update!(disposition: disposition, status: :processed, storage_location: loc)
          line.wms_return.refresh_status!
          render json: { data: { line_id: line.id, disposition: disposition, loc_code: loc.loc_code }, meta: meta }
        rescue ::Wms::ReturnService::Error => e
          render json: { error: { code: "return_failed", message: e.message } }, status: :unprocessable_entity
        end

        private

        def line_json(l)
          p = l.product
          { id: l.id, ref: l.wms_return.ref, store_code: l.wms_return.store&.store_code,
            product_id: l.product_id, sku: p&.sku, description: p&.description,
            it_barcode: p&.it_barcode, cs_barcode: p&.cs_barcode,
            qty: l.qty, uom: l.uom, pcs_per_case: p&.pcs_per_case || 1,
            suggestions: {
              saleable: ::Wms::ReturnService.suggest_location(warehouse, p, "saleable", loose: l.pc?)&.loc_code,
              damaged: ::Wms::ReturnService.suggest_location(warehouse, p, "damaged")&.loc_code,
              quarantine: ::Wms::ReturnService.suggest_location(warehouse, p, "quarantine")&.loc_code,
            } }
        end
      end
    end
  end
end
