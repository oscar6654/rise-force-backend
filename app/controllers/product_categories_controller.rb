class ProductCategoriesController < ApplicationController
  before_action -> { authorize!(:product_category, :view) }, only: [:index]
  before_action -> { authorize!(:product_category, :create) }, only: [:new, :create]
  before_action -> { authorize!(:product_category, :update) }, only: [:edit, :update]
  before_action :set_category, only: [:edit, :update]

  def index
    @categories = ProductCategory.ordered
  end

  def new
    @category = ProductCategory.new
  end

  def create
    @category = ProductCategory.new(category_params)
    if @category.save
      redirect_to product_categories_path, notice: "Category created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @category.update(category_params)
      redirect_to product_categories_path, notice: "Category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_category
    @category = ProductCategory.find(params[:id])
  end

  def category_params
    params.require(:product_category).permit(:code, :name, :status)
  end
end
