# Field-manager logins for the mobile team view. Gated on the seller resource
# (managers are a facet of managing the field team).
class ManagersController < ApplicationController
  before_action -> { authorize!(:seller, :view) }, only: [:index]
  before_action -> { authorize!(:seller, :create) }, only: [:new, :create]
  before_action -> { authorize!(:seller, :update) }, only: [:edit, :update]
  before_action :set_manager, only: [:edit, :update]

  def index
    @managers = Manager.includes(:branch).order(:name).page(params[:page]).per(25)
  end

  def new
    @manager = Manager.new
  end

  def create
    @manager = Manager.new(manager_params)
    if @manager.save
      redirect_to managers_path, notice: "Manager created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @manager.update(manager_params)
      redirect_to managers_path, notice: "Manager updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_manager
    @manager = Manager.find(params[:id])
  end

  def manager_params
    permitted = params.require(:manager).permit(:code, :name, :branch_id, :status, :pin)
    permitted.delete(:pin) if permitted[:pin].blank? # blank -> keep existing PIN
    permitted
  end
end
