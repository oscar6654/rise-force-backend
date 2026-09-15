require "csv"

class JobLogsController < ApplicationController
  before_action -> { authorize!(:job_log, :view) }
  before_action :set_log, only: [:show, :rejected_csv]

  def index
    @logs = JobLog.includes(:triggered_by).recent.page(params[:page]).per(30)
    # Drives the auto-refresh: only poll while something is actually running.
    @has_active_jobs = JobLog.where(status: [:pending, :running]).exists?
  end

  def show; end

  # Download the rejected rows from an import as CSV.
  def rejected_csv
    rows = @log.rejected_records_data
    csv = CSV.generate do |out|
      out << ["line", "error", "data"]
      rows.each { |r| out << [r["line"], r["error"], r["row"].to_json] }
    end
    send_data csv, filename: "rejected-#{@log.id}.csv", type: "text/csv"
  end

  private

  def set_log
    @log = JobLog.find(params[:id])
  end
end
