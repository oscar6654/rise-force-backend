class PricingVersionsController < ApplicationController
  before_action -> { authorize!(:pricing, :view) }, only: [:index, :show]
  before_action -> { authorize!(:pricing, :create) }, only: [:new, :create]
  before_action -> { authorize!(:pricing, :update) }, only: [:edit, :update]
  before_action -> { authorize!(:pricing, :publish) }, only: [:publish]
  before_action :set_version, only: [:show, :edit, :update, :publish]
  before_action :load_masters

  def index
    @current = PricingVersion.current
    @versions = PricingVersion.order(version_number: :desc)
  end

  def show
    @matrix = matrix_for(@version)
  end

  def new
    @version = PricingVersion.new(effective_date: Date.current)
  end

  # Create a new draft, cloning the current published matrix where present.
  def create
    @version = PricingVersion.new(version_params)
    if @version.save
      seed_rules(@version)
      redirect_to edit_pricing_version_path(@version), notice: "Draft version created. Set markups and publish."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @matrix = matrix_for(@version)
  end

  def update
    apply_markups(@version, params[:markups] || {})
    redirect_to edit_pricing_version_path(@version), notice: "Markups saved."
  end

  def publish
    @version.publish!(current_user)
    redirect_to pricing_versions_path, notice: "Published v#{@version.version_number}. Applies at next seller sync."
  end

  private

  def set_version
    @version = PricingVersion.find(params[:id])
  end

  # Rows/cols of the matrix come from the flexible masters.
  def load_masters
    @categories = StoreCategory.active.ordered
    @tiers = ProductTier.active.ordered
  end

  def version_params
    params.require(:pricing_version).permit(:name, :effective_date, :notes)
  end

  # { [store_category_id, product_tier_id] => rule }
  def matrix_for(version)
    version.pricing_rules.index_by { |r| [r.store_category_id, r.product_tier_id] }
  end

  def seed_rules(version)
    base = PricingVersion.current
    existing = base ? base.pricing_rules.index_by { |r| [r.store_category_id, r.product_tier_id] } : {}
    @categories.each do |cat|
      @tiers.each do |tier|
        rate = existing[[cat.id, tier.id]]&.markup_rate || 0
        version.pricing_rules.create!(store_category: cat, product_tier: tier, markup_rate: rate)
      end
    end
  end

  # params[:markups][store_category_id][product_tier_id] = percent
  def apply_markups(version, markups)
    markups.each do |cat_id, tiers|
      tiers.each do |tier_id, rate|
        rule = version.pricing_rules.find_or_initialize_by(store_category_id: cat_id, product_tier_id: tier_id)
        rule.markup_rate = rate.to_d / 100 # UI captures percent
        rule.save!
      end
    end
  end
end
