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
      raw = io_or_string.respond_to?(:read) ? io_or_string.read : io_or_string.to_s
      @data = normalize_encoding(raw)
      @user = user
      @filename = filename
      @log = log
    end

    # Excel exports are often Windows-1252 (or UTF-8 with stray non-breaking
    # spaces / a BOM), which crash CSV parsing as "\xA0 from ASCII-8BIT to
    # UTF-8". Coerce to clean UTF-8: transcode from Windows-1252 when it isn't
    # valid UTF-8, strip a leading BOM, and turn non-breaking spaces into normal
    # spaces so they don't break value/code matching.
    def normalize_encoding(str)
      s = str.to_s.dup.b                                                     # work in raw bytes
      s = s.byteslice(3..-1).to_s if s.byteslice(0, 3) == "\xEF\xBB\xBF".b   # strip a UTF-8 BOM first
      s.force_encoding("UTF-8")
      s = s.force_encoding("Windows-1252").encode("UTF-8", invalid: :replace, undef: :replace) unless s.valid_encoding?
      s.gsub("\u00A0", " ") # non-breaking spaces -> normal space
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
