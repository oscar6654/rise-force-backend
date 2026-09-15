class StoresController < ApplicationController
  before_action -> { authorize!(:store, :view) }, only: [:index, :show]
  before_action -> { authorize!(:store, :create) }, only: [:new, :create]
  before_action -> { authorize!(:store, :update) }, only: [:edit, :update]
  before_action :set_store, only: [:show, :edit, :update]

  def index
    scope = branch_scoped(Store.includes(:channel, :route, :branch, :seller, :store_category)).search(params[:q])
    scope = scope.where(channel_id: params[:channel_id]) if params[:channel_id].present?
    scope = scope.where(store_category_id: params[:category]) if params[:category].present?
    scope = scope.where("seller_id = :s OR route_id IN (SELECT id FROM routes WHERE seller_id = :s)", s: params[:seller_id]) if params[:seller_id].present?
    scope = scope.where(branch_id: params[:branch_id]) if params[:branch_id].present? && branch_filterable?
    @stores = scope.order(:name).page(params[:page]).per(25)
    @channels = Channel.order(:name)
  end

  def show
    @month = Date.current.beginning_of_month
    @store_target = StoreTarget.for_month(@month).find_by(store: @store)
    @confirmed = @store.confirmed_actual(@month)
    @pending_presell = @store.pending_presell(@month)
    @blended = @confirmed + @pending_presell
    @last_sellout_sync = SelloutSnapshot.store_last_synced_at(@store, month: @month)
    @attainment = @store.attainment_pct(@month)

    @compliance = @store.assortment_compliance
    if @compliance && @compliance[:gap_product_ids].any?
      @gap_products = Product.where(id: @compliance[:gap_product_ids]).order(:sku).pluck(:sku, :description)
    end
  end

  def new
    @store = Store.new(branch_id: default_branch_id, status: :active)
  end

  def create
    @store = Store.new(store_params)
    @store.branch_id ||= default_branch_id
    authorize_branch!(@store)
    if @store.save
      redirect_to stores_path, notice: "Store created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    authorize_branch!(@store)
    if @store.update(store_params)
      redirect_to store_path(@store), notice: "Store updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_store
    @store = Store.find(params[:id])
    authorize_branch!(@store)
  end

  def store_params
    permitted = params.require(:store).permit(:store_code, :name, :owner_name, :contact_number,
                :address, :latitude, :longitude, :channel_id, :route_id, :seller_id, :category_code, :status,
                :visit_frequency, :week_pattern, :visit_day, :visit_sequence, :vcsi_customer_ref, :branch_id,
                :segment, :chain, :sub_chain, :distribution_type, :tin)
    # Branch-scoped users cannot reassign the branch.
    permitted[:branch_id] = current_user.branch_id if current_user.branch_scoped?
    permitted
  end
end
