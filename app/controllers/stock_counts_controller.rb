require "csv"

# In-store shelf audits (field capture) — read + CSV export for merchandising.
# StockCount has no branch_id of its own; it's reached via visit -> store.
class StockCountsController < ApplicationController
  before_action -> { authorize!(:stock_count, :view) }, only: [:index]
  before_action -> { authorize!(:stock_count, :download) }, only: [:download]

  def index
    @filter_branches = filter_branches
    @counts = filtered.order("stock_counts.created_at DESC").page(params[:page]).per(50)
  end

  def download
    send_data csv_for(filtered.order("stock_counts.created_at DESC")),
              filename: "stock_counts_#{Date.current}.csv", type: "text/csv"
  end

  private

  # Scope to the user's accessible branches, then apply branch + date filters.
  def filtered
    scope = StockCount.joins(visit: { store: :branch }).includes(:product, visit: %i[store seller])
    scope = scope.where(stores: { branch_id: current_user.accessible_branch_ids }) unless current_user.all_branches?
    scope = scope.where(stores: { branch_id: params[:branch_id] }) if params[:branch_id].present?
    scope = with_date_range(scope, "stock_counts.created_at")
    scope
  end

  def with_date_range(scope, column)
    if params[:from].present?
      scope = scope.where("#{column} >= ?", Date.parse(params[:from]).beginning_of_day) rescue scope
    end
    if params[:to].present?
      scope = scope.where("#{column} <= ?", Date.parse(params[:to]).end_of_day) rescue scope
    end
    scope
  end

  def filter_branches
    current_user.all_branches? ? Branch.order(:name) : Branch.where(id: current_user.accessible_branch_ids).order(:name)
  end

  def csv_for(scope)
    CSV.generate do |csv|
      csv << %w[branch store_code store_name seller visit_date sku product qty prefilled_from captured_at]
      scope.find_each do |c|
        v = c.visit
        csv << [v.store&.branch&.name, v.store&.store_code, v.store&.name, v.seller&.name,
                v.visit_date, c.product&.sku, c.product&.description, c.qty,
                c.prefilled_from, c.created_at.iso8601]
      end
    end
  end
end
