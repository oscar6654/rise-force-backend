class IncentiveSchemesController < ApplicationController
  before_action -> { authorize!(:incentive_scheme, :view) }, only: [:index]
  before_action -> { authorize!(:incentive_scheme, :create) }, only: [:new, :create]
  before_action -> { authorize!(:incentive_scheme, :update) }, only: [:edit, :update, :destroy]
  before_action :set_scheme, only: [:edit, :update, :destroy]

  def index
    @schemes = IncentiveScheme.order(:scheme_type, :name).includes(:branch)
  end

  def new
    @scheme = IncentiveScheme.new(status: :active, scheme_type: :target_multiplier)
  end

  def create
    @scheme = IncentiveScheme.new(scheme_params)
    apply_config
    if @config_error.nil? && @scheme.save
      redirect_to incentive_schemes_path, notice: "Incentive scheme created."
    else
      flash.now[:alert] = @config_error if @config_error
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @scheme.assign_attributes(scheme_params)
    apply_config
    if @config_error.nil? && @scheme.save
      redirect_to incentive_schemes_path, notice: "Incentive scheme updated."
    else
      flash.now[:alert] = @config_error if @config_error
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @scheme.destroy
    redirect_to incentive_schemes_path, notice: "Incentive scheme removed."
  end

  private

  def set_scheme
    @scheme = IncentiveScheme.find(params[:id])
  end

  def scheme_params
    params.require(:incentive_scheme).permit(:name, :scheme_type, :status, :branch_id, :effective_from, :effective_to)
  end

  # config is edited as JSON so any scheme shape is supported; parse + validate.
  def apply_config
    raw = params.dig(:incentive_scheme, :config_json).to_s.strip
    return if raw.blank? && @scheme.config.present?

    @scheme.config = raw.blank? ? {} : JSON.parse(raw)
  rescue JSON::ParserError => e
    @config_error = "Config JSON is invalid: #{e.message}"
  end
end
