class AssortmentsController < ApplicationController
  before_action -> { authorize!(:assortment, :view) }, only: [:index, :show]
  before_action -> { authorize!(:assortment, :create) }, only: [:new, :create]
  before_action -> { authorize!(:assortment, :update) }, only: [:edit, :update, :import_items]
  before_action :set_assortment, only: [:show, :edit, :update, :import_items]

  def index
    @assortments = Assortment.includes(:channel, :branch, :assortment_type).order(:name)
  end

  def show
    @item_count = @assortment.assortment_items.count
    @items = @assortment.assortment_items.includes(:product)
                        .joins(:product).order(:priority, "products.sku")
                        .page(params[:page]).per(50)
  end

  def new
    @assortment = Assortment.new
  end

  def create
    @assortment = Assortment.new(assortment_params)
    @assortment.product_ids = product_ids_from_barcodes
    if @assortment.save
      redirect_to assortment_path(@assortment), notice: "Assortment saved — #{@assortment.products.count} SKU(s) across #{selected_barcodes.size} barcode(s)."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  # Bulk-add SKUs to THIS assortment from a list of IT barcodes — uploaded as a
  # CSV/text file or pasted into the textarea. Each barcode expands to every
  # active SKU sharing it; existing members are skipped (append, never replace).
  # `must_stock=0` in the form adds them as optional rather than must-stock.
  def import_items
    barcodes = parse_barcodes
    return redirect_to(assortment_path(@assortment), alert: "No barcodes found — upload a file or paste a list.") if barcodes.empty?

    products = Product.active.where(it_barcode: barcodes)
    matched  = products.map(&:it_barcode).uniq
    unknown  = barcodes - matched
    must     = params[:must_stock] != "0"

    added = 0
    products.find_each do |p|
      item = AssortmentItem.find_or_initialize_by(assortment: @assortment, product: p)
      added += 1 if item.new_record?
      item.must_stock = must
      item.save!
    end

    notice = "Added #{added} new SKU(s) from #{matched.size} barcode(s)#{" (skipped #{products.count - added} already in list)" if products.count > added}."
    notice += " #{unknown.size} barcode(s) not in product master: #{unknown.first(8).join(', ')}#{'…' if unknown.size > 8}." if unknown.any?
    redirect_to assortment_path(@assortment), notice: notice
  end

  def update
    if @assortment.update(assortment_params.merge(product_ids: product_ids_from_barcodes))
      redirect_to assortment_path(@assortment), notice: "Assortment updated — #{@assortment.products.count} SKU(s)."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_assortment
    @assortment = Assortment.find(params[:id])
  end

  def assortment_params
    params.require(:assortment).permit(:name, :branch_id, :channel_id, :store_category_ref_id, :status,
                                       :assortment_type_id, :effective_from, :effective_to)
  end

  def selected_barcodes
    Array(params.dig(:assortment, :it_barcodes)).reject(&:blank?)
  end

  # Expand chosen IT barcodes to every active product sharing them.
  def product_ids_from_barcodes
    Product.active.where(it_barcode: selected_barcodes).pluck(:id)
  end

  # Collect barcodes from the uploaded file and/or the pasted textarea. Accepts
  # one-per-line or comma-separated, tolerates an "it_barcode" header line and
  # surrounding whitespace, and de-dupes.
  def parse_barcodes
    raw = +""
    raw << params[:file].read << "\n" if params[:file].respond_to?(:read)
    raw << params[:barcodes].to_s if params[:barcodes].present?
    raw.split(/[\r\n,]+/).map(&:strip).reject { |t| t.blank? || t.casecmp?("it_barcode") }.uniq
  end
end
