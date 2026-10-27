module Wms
  class StaffController < ApplicationController
    before_action -> { authorize!(:warehouse_staff, :view) }, only: [:index]
    before_action -> { authorize!(:warehouse_staff, :create) }, only: [:new, :create]
    before_action -> { authorize!(:warehouse_staff, :update) }, only: [:edit, :update]
    before_action :set_staff, only: [:edit, :update]

    def index
      @staff = WarehouseStaff.includes(:warehouse).order(:warehouse_id, :staff_code)
      @online_ids = WarehouseStaff.online.pluck(:id).to_set # logged in + recently active
    end

    def new
      @staff = WarehouseStaff.new(warehouse_id: params[:warehouse_id])
    end

    def create
      @staff = WarehouseStaff.new(staff_params)
      if @staff.save
        redirect_to wms_staff_index_path, notice: "Warehouse staff created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      # Blank PIN keeps the existing one (mirrors the seller/diser pattern).
      attrs = staff_params
      attrs = attrs.except(:pin) if attrs[:pin].blank?
      if @staff.update(attrs)
        redirect_to wms_staff_index_path, notice: "Warehouse staff updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_staff
      @staff = WarehouseStaff.find(params[:id])
    end

    def staff_params
      p = params.require(:warehouse_staff).permit(
        :warehouse_id, :seller_id, :staff_code, :name, :status, :pin, :require_scan, :zones_str, :brand_ids_str, roles: []
      )
      p[:roles] = Array(p[:roles]).reject(&:blank?)
      zones = p.delete(:zones_str)
      brands = p.delete(:brand_ids_str)
      p[:zones] = zones.to_s.split(/[;,]/).map(&:strip).reject(&:blank?) if zones
      p[:brand_ids] = brands.to_s.split(/[;,]/).map(&:strip).reject(&:blank?).map(&:to_i) if brands
      p
    end
  end
end
