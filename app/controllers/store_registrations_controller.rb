class StoreRegistrationsController < ApplicationController
  before_action -> { authorize!(:store_registration, :view) }, only: [:index, :show]
  before_action -> { authorize!(:store_registration, :approve) }, only: [:approve, :reject]
  before_action :set_registration, only: [:show, :approve, :reject]

  def index
    scope = branch_scoped(StoreRegistration.includes(:seller, :branch, :duplicate_of_store))
    @pending = scope.pending.order(created_at: :asc)
    @recent = scope.where.not(status: :pending).order(reviewed_at: :desc).limit(20)
    @flagged_count = @pending.count(&:flagged_duplicate?)
  end

  def show; end

  def approve
    authorize_branch!(@registration)
    duplicate = params[:duplicate_of_store_id].presence && Store.find(params[:duplicate_of_store_id])
    code = params[:permanent_code].presence || suggested_code
    store = @registration.approve!(reviewer: current_user, permanent_code: code, duplicate_of: duplicate,
                                   channel_id: params[:channel_id], category_code: params[:category_code],
                                   route_id: params[:route_id], visit_day: params[:visit_day],
                                   visit_frequency: params[:visit_frequency], week_pattern: params[:week_pattern])
    redirect_to store_registrations_path, notice: "Approved — store #{store.code} is now active."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to store_registration_path(@registration), alert: "Approve failed: #{e.message}"
  end

  # Set the default category new enrollments start on (drives their price list
  # until a reviewer reassigns it). Global config, so gated on system_setting.
  def default_category
    authorize!(:system_setting, :update)
    SystemSetting.set("default_enrollment_category", params[:default_enrollment_category].to_s,
                      category: "stores",
                      description: "StoreCategory code a newly enrolled store starts on (sets its price list until a reviewer reassigns it)")
    redirect_to store_registrations_path, notice: "New stores now enroll as “#{params[:default_enrollment_category].to_s.titleize}”."
  end

  def reject
    authorize_branch!(@registration)
    @registration.reject!(reviewer: current_user, reason: params[:rejection_reason])
    redirect_to store_registrations_path, notice: "Registration rejected."
  end

  private

  def set_registration
    @registration = StoreRegistration.find(params[:id])
    authorize_branch!(@registration)
  end

  def suggested_code
    "#{@registration.branch.code}-#{format('%06d', Store.where(branch_id: @registration.branch_id).maximum(:id).to_i + 1)}"
  end
end
