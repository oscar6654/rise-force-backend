require "csv"

class DisplayCampaignsController < ApplicationController
  before_action -> { authorize!(:display_campaign, :view) }, only: [:index, :show, :store, :unmatched]
  before_action -> { authorize!(:display_campaign, :create) }, only: [:new, :create, :evidence]
  before_action -> { authorize!(:display_campaign, :destroy) }, only: [:destroy]
  before_action :set_campaign, only: [:show, :destroy, :evidence, :store, :unmatched]

  def index
    @campaigns = DisplayCampaign.order(created_at: :desc)
  end

  def new
    @campaign = DisplayCampaign.new(period_from: Date.current.beginning_of_month,
                                    period_to: Date.current.end_of_month)
  end

  # Upload the xlsx base file → creates the campaign and loads its target lines.
  def create
    file = params[:file]
    @campaign = DisplayCampaign.new(campaign_params)
    @campaign.source_filename = file&.original_filename
    @campaign.created_by = current_user

    if file.blank?
      @campaign.errors.add(:base, "Choose the target .xlsx file.")
      return render(:new, status: :unprocessable_entity)
    end
    unless @campaign.save
      return render(:new, status: :unprocessable_entity)
    end

    log = Import::DisplayTargetsImporter.new(file.tempfile.path, campaign: @campaign,
                                             user: current_user, filename: file.original_filename).call
    redirect_to display_campaign_path(@campaign),
                notice: "Loaded #{log.processed_rows}/#{log.total_rows} target rows" \
                        "#{log.error_count.positive? ? " (#{log.error_count} rejected — see Logs)" : ""}. " \
                        "Now upload the execution CSV below."
  rescue StandardError => e
    @campaign&.destroy
    redirect_to new_display_campaign_path, alert: "Upload failed: #{e.message}"
  end

  # Upload / replace the CSV execution evidence (newest supersedes).
  def evidence
    file = params[:file]
    return redirect_to(display_campaign_path(@campaign), alert: "Choose a CSV file.") if file.blank?

    log = Import::DisplayEvidenceImporter.new(file.read, campaign: @campaign,
                                              user: current_user, filename: file.original_filename).call
    redirect_to display_campaign_path(@campaign),
                notice: "Evidence updated: #{log.processed_rows}/#{log.total_rows} rows" \
                        "#{log.error_count.positive? ? " (#{log.error_count} rejected)" : ""}. Previous CSV superseded."
  rescue StandardError => e
    redirect_to display_campaign_path(@campaign), alert: "Evidence upload failed: #{e.message}"
  end

  def show
    report = DisplayReport.new(@campaign).by_store
    stores = Store.where(id: report.keys).includes(:seller).index_by(&:id)
    @rows = report.map do |sid, r|
      s = stores[sid]
      { store: s, store_id: sid, name: s&.name || sid, code: s&.store_code,
        seller: s&.seller&.name, must: r[:must], done: r[:done], missing: r[:missing],
        pct: r[:must].positive? ? (r[:done] * 100.0 / r[:must]).round : 0 }
    end.sort_by { |x| [-x[:missing], x[:name].to_s] }
    @targets_count = @campaign.display_targets.count
    @evidence_count = @campaign.display_evidences.count
    # Store codes from the xlsx that aren't in our store master → they can't
    # appear in the seller/manager app until the store is added/linked.
    @unmatched_codes = @campaign.display_targets.where(store_id: nil).distinct.order(:store_code).pluck(:store_code)

    respond_to do |format|
      format.html
      format.csv { send_data report_csv(@rows), filename: "display_targets_#{@campaign.id}.csv", type: "text/csv" }
    end
  end

  # Downloadable list of store codes that didn't match the store master.
  def unmatched
    codes = @campaign.display_targets.where(store_id: nil).distinct.order(:store_code).pluck(:store_code)
    csv = CSV.generate do |c|
      c << %w[unmatched_store_code]
      codes.each { |code| c << [code] }
    end
    send_data csv, filename: "unmatched_stores_#{@campaign.id}.csv", type: "text/csv"
  end

  # Per-store drill: each target line with its execution status + photos.
  def store
    @store = Store.find(params[:store_id])
    @summary = DisplayReport.new(@campaign, store_ids: [@store.id]).by_store[@store.id] ||
               { lines: [], must: 0, done: 0, missing: 0 }
  end

  def destroy
    @campaign.destroy
    redirect_to display_campaigns_path, notice: "Campaign deleted."
  end

  private

  def set_campaign
    @campaign = DisplayCampaign.find(params[:id])
  end

  def campaign_params
    params.require(:display_campaign).permit(:name, :period_from, :period_to)
  end

  def report_csv(rows)
    CSV.generate do |csv|
      csv << %w[store_code store_name seller targets executed missing pct]
      rows.each { |r| csv << [r[:code], r[:name], r[:seller], r[:must], r[:done], r[:missing], r[:pct]] }
    end
  end
end
