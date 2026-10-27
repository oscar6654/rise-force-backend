require "csv"

class OrderBatchesController < ApplicationController
  before_action -> { authorize!(:order_batch, :view) }, only: [:index, :show]
  before_action -> { authorize!(:order_batch, :download) }, only: [:build, :download]
  before_action :set_batch, only: [:show, :download]

  def index
    @filter_branches = current_user&.all_branches? ? Branch.order(:name) : Branch.where(id: current_user.accessible_branch_ids).order(:name)
    scope = branch_scoped(OrderBatch.includes(:branch, :seller, :downloaded_by))
    scope = scope.where(branch_id: params[:branch_id]) if params[:branch_id].present?
    if params[:from].present?
      begin
        scope = scope.where("created_at >= ?", Date.parse(params[:from]).beginning_of_day)
      rescue ArgumentError
      end
    end
    if params[:to].present?
      begin
        scope = scope.where("created_at <= ?", Date.parse(params[:to]).end_of_day)
      rescue ArgumentError
      end
    end
    @batches = scope.order(created_at: :desc).page(params[:page]).per(30)
    # Sellers with unbatched orders — the "next batch to download" candidates.
    # WMS-routed orders are excluded until dispatched (they're handled in the WMS,
    # not the OSB batch), so an operator never sees — or clicks — an order that
    # is actually being picked/packed.
    @pending = branch_scoped(Order.batchable_pending).group(:branch_id, :seller_id)
               .select("branch_id, seller_id, COUNT(*) AS order_count, SUM(total_amount) AS total")
    @sellers = Seller.where(id: @pending.map(&:seller_id)).index_by(&:id)
    # How many unbatched orders are currently in the WMS (for an info note).
    @wms_held_count = branch_scoped(Order.unbatched.wms_held).count
  end

  def show
    @orders = @batch.orders.includes(:store, :order_lines)
  end

  # Create the next batch for a (branch, seller).
  def build
    seller = Seller.find(params[:seller_id])
    # Build for the branch the ORDERS are in (from the pending row), not the
    # seller's master branch — for a login-group / OSB rep the two can differ
    # (orders carry the store's branch), and build_for scopes by branch + seller,
    # so using seller.branch would find nothing ("No unbatched orders").
    branch = params[:branch_id].present? ? Branch.find(params[:branch_id]) : seller.branch
    authorize_branch!(branch, column: :id)
    batch = OrderBatch.build_for(branch: branch, seller: seller, user: current_user)
    if batch
      redirect_to order_batch_path(batch), notice: "Built #{batch.batch_number} — #{batch.order_count} orders. Ready to download."
    else
      redirect_to order_batches_path, alert: "No unbatched orders for #{seller.name}."
    end
  end

  # Download once (locks against double-download / double-invoicing) and stream CSV.
  def download
    authorize_branch!(@batch)
    @batch.download!(current_user)
    send_data batch_csv(@batch), filename: "#{@batch.batch_number}.csv", type: "text/csv"
  rescue OrderBatch::AlreadyDownloaded
    redirect_to order_batch_path(@batch),
                alert: "Already downloaded on #{@batch.downloaded_at&.strftime('%d %b %H:%M')} by #{@batch.downloaded_by&.full_name}. Re-download blocked to prevent double invoicing."
  end

  private

  def set_batch
    @batch = OrderBatch.find(params[:id])
    authorize_branch!(@batch)
  end

  def batch_csv(batch)
    CSV.generate do |csv|
      csv << %w[order_number store_code delivery_date remarks it_barcode cs_barcode qty_cases qty_pieces unit_price line_total]
      batch.orders.includes(:store, order_lines: :product).find_each do |order|
        order.order_lines.each do |line|
          # For a WMS order, shipped_qty (net of short picks) is authoritative;
          # fall back to the ordered quantity for non-WMS orders. Same uom as the line.
          effective = line.shipped_qty.presence || line.quantity
          qty_cases  = line.uom_case_uom? ? effective : 0
          qty_pieces = line.uom_pc? ? effective : 0
          csv << [order.order_number, order.store.code, order.delivery_date, order.notes,
                  line.product.it_barcode, line.product.cs_barcode,
                  qty_cases, qty_pieces, line.unit_price, line.line_total]
        end
      end
    end
  end
end
