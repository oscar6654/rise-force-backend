# Admin-managed assortment types. Reuses the :assortment RBAC resource — anyone
# who can edit assortments can manage the type list.
class AssortmentTypesController < ApplicationController
  before_action -> { authorize!(:assortment, :view) }, only: [:index]
  before_action -> { authorize!(:assortment, :create) }, only: [:new, :create]
  before_action -> { authorize!(:assortment, :update) }, only: [:edit, :update]
  before_action -> { authorize!(:assortment, :update) }, only: [:destroy]
  before_action :set_type, only: [:edit, :update, :destroy]

  def index
    @types = AssortmentType.ordered
  end

  def new
    @type = AssortmentType.new(active: true, position: (AssortmentType.maximum(:position) || 0) + 1)
  end

  def create
    @type = AssortmentType.new(type_params)
    if @type.save
      redirect_to assortment_types_path, notice: "Type “#{@type.name}” added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @type.update(type_params)
      redirect_to assortment_types_path, notice: "Type updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @type.destroy
      redirect_to assortment_types_path, notice: "Type removed."
    else
      # restrict_with_error when assortments still reference it.
      redirect_to assortment_types_path, alert: "Can’t remove a type that’s in use — reassign or deactivate it instead."
    end
  end

  private

  def set_type
    @type = AssortmentType.find(params[:id])
  end

  # code is only settable on create (it's the stable key configs reference);
  # after that only name/position/active can change.
  def type_params
    permitted = @type&.persisted? ? %i[name position active] : %i[code name position active]
    params.require(:assortment_type).permit(*permitted)
  end
end
