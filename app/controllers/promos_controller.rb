class PromosController < ApplicationController
  before_action -> { authorize!(:promo, :view) }, only: [:index, :show]
  before_action -> { authorize!(:promo, :create) }, only: [:new, :create]
  before_action -> { authorize!(:promo, :update) }, only: [:edit, :update]
  before_action :set_promo, only: [:show, :edit, :update]

  def index
    @tab = params[:tab].presence_in(%w[active scheduled ended cancelled]) || "active"
    @promos = Promo.where(status: @tab).order(:start_date)
  end

  def show
    @lines = @promo.promo_lines.includes(:product)
    # The item_keys this promo actually applies to = active SKUs sharing any of
    # its lines' IT barcodes (what the app sees). Paginated — one barcode can
    # cover 100+ SKUs.
    barcodes = @lines.map(&:it_barcode).compact_blank.uniq
    scope = Product.active.where(it_barcode: barcodes)
    @sku_count = scope.count
    @skus = scope.includes(:brand).order(:sku).page(params[:page]).per(50)
  end

  def new
    @promo = Promo.new(status: :scheduled)
    @promo.promo_lines.build # one starter mechanic line
  end

  def create
    @promo = Promo.new(promo_params)
    @promo.created_by = current_user
    apply_config(@promo)
    if @promo.save
      apply_eligibility(@promo)
      redirect_to promo_path(@promo), notice: "Promo created. Add mechanics next."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @promo.assign_attributes(promo_params)
    apply_config(@promo)
    if @promo.save
      apply_eligibility(@promo)
      redirect_to promo_path(@promo), notice: "Promo updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # Build the tiered-discount config from the form's basis + compact tiers string.
  def apply_config(promo)
    return unless promo.mechanic_type == "tiered_discount"

    basis = params.dig(:promo, :config_basis).presence || "pieces"
    promo.config = { "basis" => basis, "tiers" => Promo.parse_tiers(params.dig(:promo, :config_tiers), basis) }
  end

  # Replace the promo's eligibility from the form (mirrors the CSV upload's
  # rebuild_eligibility). One row per selected channel so a promo can cover
  # 2–3 channels; category/branch (if set) apply to each. All blank = every store.
  def apply_eligibility(promo)
    channel_ids = Array(params.dig(:promo, :eligibility_channel_ids)).reject(&:blank?)
    category_id = params.dig(:promo, :eligibility_store_category_ref_id).presence
    branch_id   = params.dig(:promo, :eligibility_branch_id).presence

    promo.promo_eligibilities.destroy_all
    if channel_ids.any?
      channel_ids.each { |cid| promo.promo_eligibilities.create!(channel_id: cid, store_category_ref_id: category_id, branch_id: branch_id) }
    elsif category_id.present? || branch_id.present?
      promo.promo_eligibilities.create!(store_category_ref_id: category_id, branch_id: branch_id)
    end
  end

  def set_promo
    @promo = Promo.find(params[:id])
  end

  def promo_params
    params.require(:promo).permit(:code, :name, :mechanic_type, :description,
                                  :start_date, :end_date, :status, :per_store_limit,
                                  promo_lines_attributes: [:id, :role, :it_barcode, :product_id, :min_qty,
                                                           :reward_qty, :discount_rate,
                                                           :discount_amount, :fixed_price, :_destroy])
  end
end
