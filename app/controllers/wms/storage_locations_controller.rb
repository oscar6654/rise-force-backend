module Wms
  class StorageLocationsController < ApplicationController
    before_action -> { authorize!(:storage_location, :view) }, only: [:index]
    before_action -> { authorize!(:storage_location, :create) }, only: [:new, :create]
    before_action -> { authorize!(:storage_location, :update) }, only: [:edit, :update]
    before_action :set_location, only: [:edit, :update]

    def index
      scope = StorageLocation.includes(:warehouse)
      scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
      @warehouses = Warehouse.order(:whs_code)
      @locations = scope.order(:warehouse_id, :pick_sequence, :loc_code).page(params[:page]).per(50)
    end

    def new
      @location = StorageLocation.new(warehouse_id: params[:warehouse_id])
    end

    def create
      @location = StorageLocation.new(location_params)
      if @location.save
        redirect_to wms_storage_locations_path, notice: "Location created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @location.update(location_params)
        redirect_to wms_storage_locations_path, notice: "Location updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_location
      @location = StorageLocation.find(params[:id])
    end

    def location_params
      p = params.require(:storage_location).permit(
        :warehouse_id, :loc_code, :name, :zone, :aisle, :bay, :level, :loc_type, :pickable,
        :allow_mixed_lots, :slot_capacity, :pick_sequence, :status, :allowed_abc_classes_str, :allowed_brand_ids_str
      )
      # Comma/semicolon lists from the form → arrays.
      abc = p.delete(:allowed_abc_classes_str)
      brands = p.delete(:allowed_brand_ids_str)
      p[:allowed_abc_classes] = abc.to_s.split(/[;,]/).map { |s| s.strip.upcase }.reject(&:blank?) if abc
      p[:allowed_brand_ids] = brands.to_s.split(/[;,]/).map(&:strip).reject(&:blank?).map(&:to_i) if brands
      p
    end
  end
end
