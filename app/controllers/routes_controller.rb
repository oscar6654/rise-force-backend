class RoutesController < ApplicationController
  before_action -> { authorize!(:route_plan, :view) }, only: [:index, :show]
  before_action -> { authorize!(:route_plan, :update) }, only: [:new, :create, :edit, :update]
  before_action :set_route, only: [:show, :edit, :update]

  def index
    @routes = branch_scoped(Route.includes(:seller, :branch, :stores)).order(:code)
                .page(params[:page]).per(25)
  end

  def show
    @stores = @route.stores.order(:visit_day, :visit_sequence)
    @calendar = coverage_calendar(@stores)
  end

  # Bulk-save per-store frequency settings from the editor grid.
  def update_frequencies
    authorize!(:route_plan, :update)
    authorize_branch!(@route)
    updates = params[:stores] || {}
    Store.transaction do
      updates.each do |store_id, attrs|
        store = @route.stores.find_by(id: store_id)
        next unless store

        store.update!(attrs.permit(:visit_frequency, :week_pattern, :visit_day, :visit_sequence))
      end
    end
    redirect_to route_path(@route), notice: "Frequencies saved."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to route_path(@route), alert: "Save failed: #{e.message}"
  end

  def new
    @route = Route.new(branch_id: default_branch_id)
  end

  def create
    @route = Route.new(route_params)
    @route.branch_id ||= default_branch_id
    authorize_branch!(@route)
    if @route.save
      redirect_to routes_path, notice: "Route created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    authorize_branch!(@route)
    if @route.update(route_params)
      redirect_to route_path(@route), notice: "Route updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_route
    @route = Route.find(params[:id])
    authorize_branch!(@route)
  end

  def route_params
    permitted = params.require(:route).permit(:code, :name, :seller_id, :status, :branch_id)
    permitted[:branch_id] = current_user.branch_id if current_user.branch_scoped?
    permitted
  end

  # Count of stores due each (week, weekday) across a representative month,
  # for the coverage preview grid. Weeks 1..4, Mon..Sat.
  def coverage_calendar(stores)
    grid = Array.new(4) { Array.new(6, 0) }
    month_start = Time.zone.today.beginning_of_month
    (0...28).each do |offset|
      date = month_start + offset.days
      next if date.wday.zero? # skip Sundays
      week = ((date.day - 1) / 7)      # 0..3
      weekday = date.wday - 1          # 0(Mon)..5(Sat)
      next if weekday > 5
      stores.each { |s| grid[week][weekday] += 1 if s.due_on?(date) }
    end
    grid
  end
end
