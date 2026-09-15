class PlanogramsController < ApplicationController
  before_action -> { authorize!(:planogram, :view) }, only: [:index, :show]
  before_action -> { authorize!(:planogram, :create) }, only: [:new, :create]
  before_action -> { authorize!(:planogram, :update) }, only: [:edit, :update]
  before_action :set_planogram, only: [:show, :edit, :update]

  def index
    @planograms = Planogram.includes(:channel).order(created_at: :desc)
  end

  def show; end

  def new
    @planogram = Planogram.new
  end

  def create
    @planogram = Planogram.new(planogram_params)
    @planogram.uploaded_by = current_user
    if @planogram.save
      redirect_to planograms_path, notice: "Planogram uploaded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @planogram.update(planogram_params)
      redirect_to planograms_path, notice: "Planogram updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_planogram
    @planogram = Planogram.find(params[:id])
  end

  def planogram_params
    params.require(:planogram).permit(:channel_id, :title, :status, :effective_date, :file)
  end
end
