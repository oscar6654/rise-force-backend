module Visits
  # Nightly: auto-close visits left in-progress (past-day open + same-day
  # duplicates), so a forgotten check-out or a duplicate check-in doesn't
  # linger in the Field Visits report. See Visits::Housekeeping.
  class CloseStaleVisitsJob < ApplicationJob
    queue_as :default

    def perform
      closed = Visits::Housekeeping.close_stale!
      Rails.logger.info("[CloseStaleVisitsJob] auto-closed #{closed} stale in-progress visits")
      closed
    end
  end
end
