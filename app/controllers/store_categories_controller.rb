class StoreCategoriesController < ApplicationController
  before_action -> { authorize!(:store_category, :view) }, only: [:index]
  before_action -> { authorize!(:store_category, :create) }, only: [:new, :create]
  before_action -> { authorize!(:store_category, :update) }, only: [:edit, :update]
  before_action :set_category, only: [:edit, :update]

  def index
    @categories = StoreCategory.ordered
  end

  def new
    @category = StoreCategory.new(active: true)
  end

  def create
    @category = StoreCategory.new(category_params)
    if @category.save
      redirect_to store_categories_path, notice: "Category created — it now appears in the pricing matrix."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @category.update(category_params)
      redirect_to store_categories_path, notice: "Category updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_category
    @category = StoreCategory.find(params[:id])
  end

  def category_params
    params.require(:store_category).permit(:code, :name, :letter, :sort_order, :active)
  end
end
