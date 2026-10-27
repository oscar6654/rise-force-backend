module Wms
  class InventoryController < ApplicationController
    before_action -> { authorize!(:inventory, :view) }, only: [:index, :move]
    before_action -> { authorize!(:storage_location, :update) }, only: [:relocate] # moving stock places it

    def index
      @warehouses = Warehouse.order(:whs_code)

      # Warehouse scope drives both the dashboard tiles and the table, so the
      # numbers match what's listed. Download CSV carries the same warehouse.
      base = InventoryLot.all
      base = base.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
      @stats = inventory_stats(base)

      scope = base.includes(:warehouse, :storage_location, :product).where("qty_on_hand > 0")
      if params[:q].present?
        q = "%#{params[:q].strip.downcase}%"
        scope = scope.joins(:product).left_joins(:storage_location)
                     .where("lower(products.sku) LIKE :q OR lower(products.description) LIKE :q OR " \
                            "lower(products.it_barcode) LIKE :q OR lower(products.cs_barcode) LIKE :q OR " \
                            "lower(storage_locations.loc_code) LIKE :q", q: q)
      end
      @lots = scope.order(:warehouse_id, :received_date).page(params[:page]).per(50)
    end

    # Form: move a lot to another location (e.g. buffer → pick slot).
    def move
      @lot = InventoryLot.includes(:warehouse, :storage_location, :product).find(params[:id])
      @locations = @lot.warehouse.storage_locations.where(status: :active).where.not(loc_type: :receiving_dock).order(:pick_sequence, :loc_code)
    end

    def relocate
      lot = InventoryLot.find(params[:id])
      dest = lot.warehouse.storage_locations.find(params.require(:to_location_id))
      ::Wms::RelocationService.new(lot, user: current_user)
                              .move!(to_location: dest, qty: params[:qty].presence)
      redirect_to wms_inventory_index_path, notice: "Moved #{lot.product.sku} → #{dest.loc_code}."
    rescue ::Wms::RelocationService::Error => e
      redirect_to move_wms_inventory_path(lot), alert: e.message
    end

    private

    # Compact inventory dashboard over the (optionally warehouse-scoped) lots:
    # on-hand/allocated/available pieces, distinct SKUs, occupied bins, and the
    # quarantine/damaged holds — one aggregate query plus a few counts.
    def inventory_stats(base)
      with_stock = base.where("qty_on_hand > 0")
      on_hand, allocated, locked, lot_count = with_stock.pick(
        Arel.sql("COALESCE(SUM(qty_on_hand),0), COALESCE(SUM(qty_allocated),0), " \
                 "COALESCE(SUM(qty_locked),0), COUNT(*)")
      )
      {
        on_hand: on_hand.to_i, allocated: allocated.to_i, locked: locked.to_i,
        available: (on_hand.to_i - allocated.to_i - locked.to_i),
        lots: lot_count.to_i,
        skus: with_stock.distinct.count(:product_id),
        locations: with_stock.where.not(storage_location_id: nil).distinct.count(:storage_location_id),
        quarantine: base.where(status: :quarantine).where("qty_on_hand > 0").count,
        damaged: base.where(status: :damaged).where("qty_on_hand > 0").count,
      }
    end
  end
end
