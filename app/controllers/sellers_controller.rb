class SellersController < ApplicationController
  before_action -> { authorize!(:seller, :view) }, only: [:index, :show]
  before_action -> { authorize!(:seller, :create) }, only: [:new, :create]
  before_action -> { authorize!(:seller, :update) }, only: [:edit, :update]
  before_action :set_seller, only: [:show, :edit, :update]

  def index
    @sellers = branch_scoped(Seller.includes(:branch, :routes)).order(:name)
                 .page(params[:page]).per(25)
  end

  def show; end

  def new
    @seller = Seller.new(branch_id: default_branch_id)
  end

  def create
    @seller = Seller.new(seller_params)
    @seller.branch_id ||= default_branch_id
    authorize_branch!(@seller)
    if @seller.save
      redirect_to sellers_path, notice: "Seller created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    authorize_branch!(@seller)
    if @seller.update(seller_params)
      redirect_to sellers_path, notice: "Seller updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_seller
    @seller = Seller.find(params[:id])
    authorize_branch!(@seller)
  end

  def seller_params
    permitted = params.require(:seller).permit(:seller_code, :name, :branch_id, :status,
                                               :device_id, :vcsi_sales_rep_ref, :user_id, :pin,
                                               :supervisor_name, :gsm_name, :om_name, :sales_target,
                                               :diser_code, :diser_name, :diser_pin, :primary_seller_id)
    permitted[:branch_id] = current_user.branch_id if current_user.branch_scoped?
    permitted.delete(:pin) if permitted[:pin].blank?             # blank -> keep existing PIN
    permitted.delete(:diser_pin) if permitted[:diser_pin].blank? # blank -> keep existing diser PIN
    permitted[:diser_code] = nil if permitted[:diser_code].blank? # blank -> no diser login
    permitted
  end
end
