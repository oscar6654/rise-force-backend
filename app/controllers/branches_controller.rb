class BranchesController < ApplicationController
  before_action -> { authorize!(:branch, :view) }, only: [:index]
  before_action -> { authorize!(:branch, :create) }, only: [:new, :create]
  before_action -> { authorize!(:branch, :update) }, only: [:edit, :update]
  before_action :set_branch, only: [:edit, :update]

  def index
    @branches = Branch.order(:code)
  end

  def new
    @branch = Branch.new(timezone: "Asia/Manila")
  end

  def create
    @branch = Branch.new(branch_params)
    if @branch.save
      redirect_to branches_path, notice: "Branch created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @branch.update(branch_params)
      redirect_to branches_path, notice: "Branch updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_branch
    @branch = Branch.find(params[:id])
  end

  def branch_params
    params.require(:branch).permit(:code, :name, :region, :timezone, :status, :vcsi_branch_ref)
  end
end
