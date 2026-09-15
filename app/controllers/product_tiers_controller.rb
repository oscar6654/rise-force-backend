class ProductTiersController < ApplicationController
  before_action -> { authorize!(:product_tier, :view) }, only: [:index]
  before_action -> { authorize!(:product_tier, :create) }, only: [:new, :create]
  before_action -> { authorize!(:product_tier, :update) }, only: [:edit, :update]
  before_action :set_tier, only: [:edit, :update]

  def index
    @tiers = ProductTier.ordered
  end

  def new
    @tier = ProductTier.new(active: true)
  end

  def create
    @tier = ProductTier.new(tier_params)
    if @tier.save
      redirect_to product_tiers_path, notice: "Tier created — it now appears in the pricing matrix."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @tier.update(tier_params)
      redirect_to product_tiers_path, notice: "Tier updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_tier
    @tier = ProductTier.find(params[:id])
  end

  def tier_params
    params.require(:product_tier).permit(:code, :name, :sort_order, :active)
  end
end
