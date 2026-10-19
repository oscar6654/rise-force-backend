class SyncsController < ApplicationController
  before_action -> { authorize!(:sync, :sync) }

  # Each maps a button on the Import Logs page to a recurring vcsi_rise sync,
  # triggerable on demand. (No "stock" entry: on-hand StockSyncJob has no vcsi
  # endpoint yet — dormant scaffolding, so there's nothing to trigger.)
  JOBS = {
    "sellout"           => "Vcsi::SelloutSyncJob",
    "targets"           => "Vcsi::TargetSyncJob",
    "store_sellout"     => "Vcsi::StoreSelloutSyncJob",
    "store_sku_sellout" => "Vcsi::StoreSkuSelloutSyncJob",
    "store_targets"     => "Vcsi::StoreTargetComputeJob",
    # AI assist — run AFTER the vcsi syncs above so they use fresh data.
    "ai_briefs"         => "Ai::DailyBriefsJob",
    "ai_weekly"         => "Ai::WeeklyRoundupJob"
  }.freeze

  # These run in the background (the Logs page auto-refreshes to show progress)
  # instead of blocking the request: the SKU pull is large; AI briefs make one
  # API call per seller/manager.
  BACKGROUND = %w[store_sku_sellout ai_briefs ai_weekly].freeze

  # Trigger a vcsi_rise sync on demand. Light syncs run inline so they work
  # without a separate worker; heavy ones enqueue (solid_queue in prod, async
  # in dev). Scheduled runs always go through solid_queue.
  def create
    job = JOBS[params[:kind]]
    return redirect_to(job_logs_path, alert: "Unknown sync.") unless job

    if BACKGROUND.include?(params[:kind])
      job.constantize.perform_later(user: current_user)
      redirect_to job_logs_path, notice: "#{params[:kind].titleize} sync queued — watch its progress below."
    else
      job.constantize.perform_now(user: current_user)
      redirect_to job_logs_path, notice: "#{params[:kind].titleize} sync finished — see the latest log."
    end
  rescue StandardError => e
    redirect_to job_logs_path, alert: "Sync failed: #{e.message}"
  end
end
