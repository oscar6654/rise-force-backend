# End-to-end view of the stock-check → offtake → predicted inventory → ICO
# engine across stores: which stores were counted, how stale, and how many
# cases they should be reordered right now. Drill into a store (its show page)
# for the per-SKU detail + CSV.
class ReplenishmentController < ApplicationController
  before_action -> { authorize!(:stock_count, :view) }

  def index
    scope = branch_scoped(Store.where.not(last_stock_checked_at: nil))
            .includes(:branch, :seller, :route)
            .search(params[:q])
    scope = scope.where(branch_id: params[:branch_id]) if params[:branch_id].present? && branch_filterable?
    scope = scope.where("seller_id = :s OR route_id IN (SELECT id FROM routes WHERE seller_id = :s)", s: params[:seller_id]) if params[:seller_id].present?
    # Filter by WHEN the store was last counted, so a period can be analysed.
    @from = parse_date(params[:from])
    @to   = parse_date(params[:to])
    scope = scope.where("last_stock_checked_at >= ?", @from.beginning_of_day) if @from
    scope = scope.where("last_stock_checked_at <= ?", @to.end_of_day) if @to
    @stores = scope.order(last_stock_checked_at: :desc).page(params[:page]).per(25)

    # Summarise each store's ICO on the current page (bounded work).
    @summaries = @stores.to_h do |s|
      rows = StoreInventoryEstimator.new(s).rows
      [s.id, {
        skus: rows.size,
        to_reorder: rows.count { |r| r.suggested_cases.positive? },
        cases: rows.sum(&:suggested_cases),
        offtake_learned: rows.count { |r| r.basis == "offtake" },
      }]
    end

    respond_to do |format|
      format.html
      format.csv do
        send_data replenishment_csv(scope.order(:name)),
                  filename: "replenishment_#{Date.current.iso8601}.csv", type: "text/csv"
      end
    end
  end

  private

  def parse_date(str)
    str.present? ? Date.parse(str) : nil
  rescue ArgumentError
    nil
  end

  def replenishment_csv(stores)
    require "csv"
    CSV.generate do |csv|
      csv << ["Store code", "Store", "Branch", "Seller", "Last checked", "Next visit",
              "SKUs", "SKUs to reorder", "Total suggested cases", "Offtake-learned SKUs"]
      stores.find_each do |s|
        rows = StoreInventoryEstimator.new(s).rows
        csv << [s.code, s.name, s.branch&.name, s.assigned_seller&.name,
                s.last_stock_checked_at&.to_date, StoreInventoryEstimator.new(s).next_visit_on,
                rows.size, rows.count { |r| r.suggested_cases.positive? },
                rows.sum(&:suggested_cases), rows.count { |r| r.basis == "offtake" }]
      end
    end
  end
end
