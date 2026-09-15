class OrdersController < ApplicationController
  before_action -> { authorize!(:order, :view) }
  before_action :set_order, only: [:show]

  def index
    @filter_branches = current_user&.all_branches? ? Branch.order(:name) : Branch.where(id: current_user.accessible_branch_ids).order(:name)
    scope = branch_scoped(Order.includes(:seller, :store, :order_batch))
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(seller_id: params[:seller_id]) if params[:seller_id].present?
    scope = scope.where(branch_id: params[:branch_id]) if params[:branch_id].present?
    if params[:from].present?
      begin
        scope = scope.where("ordered_at >= ?", Date.parse(params[:from]).beginning_of_day)
      rescue ArgumentError
      end
    end
    if params[:to].present?
      begin
        scope = scope.where("ordered_at <= ?", Date.parse(params[:to]).end_of_day)
      rescue ArgumentError
      end
    end
    @orders = scope.order(ordered_at: :desc).page(params[:page]).per(30)
  end

  def show
    @lines = @order.order_lines.includes(:product)
  end

  private

  def set_order
    @order = Order.find(params[:id])
    authorize_branch!(@order)
  end
end
