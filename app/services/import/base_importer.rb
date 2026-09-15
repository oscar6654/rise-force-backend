require "csv"

module Import
  # Base CSV importer. Subclasses define JOB_TYPE, REQUIRED_HEADERS and
  # #import_row(row). Wraps the run in a JobLog and collects rejected rows
  # (with reason) for a downloadable error report — mirrors the vcsi_rise
  # upload pattern. Processed inline for now; can be moved to a job later.
  class BaseImporter
    # #call returns the JobLog for the run. Pass an existing `log:` to run
    # against a JobLog already created by the controller (background-job path).
    def initialize(io_or_string, user:, filename: nil, log: nil)
      @data = io_or_string.respond_to?(:read) ? io_or_string.read : io_or_string.to_s
      @user = user
      @filename = filename
      @log = log
    end

    def call
      JobLog.track(self.class::JOB_TYPE, user: @user, filename: @filename, log: @log) do |log|
        rows = CSV.parse(@data, headers: true)
        log.total_rows = rows.size
        rows.each_with_index do |row, i|
          import_row(row)
          log.processed_rows += 1
        rescue StandardError => e
          log.error_count += 1
          log.rejected_records_data << { line: i + 2, error: e.message, row: row.to_h }
        end
        log.save!
      end
    end

    private

    def import_row(_row)
      raise NotImplementedError
    end
  end
end
