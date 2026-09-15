module Import
  # Runs a bulk CSV import in the background against a JobLog the controller
  # already created (with the uploaded file attached as `source_file`). Used for
  # large uploads (20k+ rows) so the web request doesn't block/time out — the
  # operator watches progress on the Import logs screen.
  class RunJob < ApplicationJob
    queue_as :default

    def perform(log_id, importer_class, kind)
      log = JobLog.find(log_id)
      data = log.source_file.download
      kwargs = { user: log.triggered_by, filename: log.filename, log: log }
      # Stores need a default branch for NEW rows without a branch_code; derive
      # it from the operator who uploaded (same as the inline path).
      kwargs[:default_branch] = log.triggered_by&.branch || Branch.first if kind == "stores"
      importer_class.constantize.new(data, **kwargs).call
    end
  end
end
