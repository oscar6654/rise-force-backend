class BrandsController < ApplicationController
  before_action -> { authorize!(:brand, :view) }, only: [:index]
  before_action -> { authorize!(:brand, :create) }, only: [:new, :create]
  before_action -> { authorize!(:brand, :update) }, only: [:edit, :update]
  before_action :set_brand, only: [:edit, :update]

  def index
    @brands = Brand.ordered
  end

  def new
    @brand = Brand.new
  end

  def create
    @brand = Brand.new(brand_params)
    if @brand.save
      redirect_to brands_path, notice: "Brand created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @brand.update(brand_params)
      redirect_to brands_path, notice: "Brand updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_brand
    @brand = Brand.find(params[:id])
  end

  def brand_params
    params.require(:brand).permit(:code, :name, :sort_order, :status)
  end
end
