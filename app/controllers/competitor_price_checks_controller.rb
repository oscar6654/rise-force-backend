require "csv"

# Shelf-price + competitor capture (field capture) — read + CSV export so the
# branch can see competitor products and prices the sellers logged. Reached via
# visit -> store (no branch_id of its own).
class CompetitorPriceChecksController < ApplicationController
  before_action -> { authorize!(:competitor_check, :view) }, only: [:index]
  before_action -> { authorize!(:competitor_check, :download) }, only: [:download]

  def index
    @filter_branches = filter_branches
    @checks = filtered.order("competitor_price_checks.created_at DESC").page(params[:page]).per(50)
  end

  def download
    send_data csv_for(filtered.order("competitor_price_checks.created_at DESC")),
              filename: "competitor_checks_#{Date.current}.csv", type: "text/csv"
  end

  private

  def filtered
    scope = CompetitorPriceCheck.joins(visit: { store: :branch }).includes(:product, visit: %i[store seller])
    scope = scope.where(stores: { branch_id: current_user.accessible_branch_ids }) unless current_user.all_branches?
    scope = scope.where(stores: { branch_id: params[:branch_id] }) if params[:branch_id].present?
    scope = with_date_range(scope, "competitor_price_checks.created_at")
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
      csv << %w[branch store_code seller visit_date our_sku our_product our_price competitor_name competitor_price notes captured_at]
      scope.find_each do |c|
        v = c.visit
        csv << [v.store&.branch&.name, v.store&.store_code, v.seller&.name, v.visit_date,
                c.product&.sku, c.product&.description || c.product_label, c.our_price,
                c.competitor_name, c.competitor_price, c.notes, c.created_at.iso8601]
      end
    end
  end
end
