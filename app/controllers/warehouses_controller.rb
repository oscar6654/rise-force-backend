class WarehousesController < ApplicationController
  before_action -> { authorize!(:warehouse, :view) }, only: [:index]
  before_action -> { authorize!(:warehouse, :create) }, only: [:new, :create]
  before_action -> { authorize!(:warehouse, :update) }, only: [:edit, :update]
  before_action :set_warehouse, only: [:edit, :update]

  def index
    @warehouses = Warehouse.includes(:branch).order(:whs_code)
  end

  def new
    @warehouse = Warehouse.new
  end

  def create
    @warehouse = Warehouse.new(warehouse_params)
    if @warehouse.save
      redirect_to warehouses_path, notice: "Warehouse created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @warehouse.update(warehouse_params)
      redirect_to warehouses_path, notice: "Warehouse updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_warehouse
    @warehouse = Warehouse.find(params[:id])
  end

  def warehouse_params
    params.require(:warehouse).permit(:whs_code, :wh_name, :branch_id, :address, :status)
  end
end
