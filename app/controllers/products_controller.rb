class ProductsController < ApplicationController
  before_action -> { authorize!(:product, :view) }, only: [:index, :show]
  before_action -> { authorize!(:product, :create) }, only: [:new, :create]
  before_action -> { authorize!(:product, :update) }, only: [:edit, :update]
  before_action :set_product, only: [:show, :edit, :update]

  def index
    @products = Product.includes(:brand, :product_category, :product_tier)
                       .search(params[:q])
    @products = @products.where(product_tier_id: params[:tier]) if params[:tier].present?
    @products = @products.order(:sku).page(params[:page]).per(25)
  end

  def show; end

  def new
    @product = Product.new
  end

  def create
    @product = Product.new(product_params)
    if @product.save
      redirect_to products_path, notice: "Product created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @product.update(product_params)
      redirect_to products_path, notice: "Product updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_product
    @product = Product.find(params[:id])
  end

  def product_params
    params.require(:product).permit(:sku, :description, :desc2, :brand_name, :category_name,
                                    :brand_form, :variant_code, :variant_name, :tier_code, :abc_class,
                                    :ordering_unit, :stock_uom, :purchase_uom, :selling_uom,
                                    :pcs_per_case, :items_per_shrinkwrap, :casesperpallet, :layersperpallet,
                                    :casestatfactor, :shrinkwraps_per_case, :caseheight, :caseweight, :casevolume,
                                    :it_barcode, :cs_barcode, :sw_barcode,
                                    :item_cost, :case_cost, :tax_code,
                                    :slideoutcode, :ovsoldcostmethod, :msq, :nspacksize, :nspacktype,
                                    :status, :photo)
  end
end
