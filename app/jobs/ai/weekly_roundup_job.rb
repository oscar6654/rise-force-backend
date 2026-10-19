module Ai
  # Manual (Import Logs) weekly manager roundup — run it at the start of the week
  # after the morning syncs. No-op unless AI is enabled + keyed.
  class WeeklyRoundupJob < ApplicationJob
    queue_as :default

    def perform(user: nil, log: nil)
      JobLog.track(:ai_weekly_roundup, user: user, log: log) do |l|
        unless Ai::Anthropic.enabled?
          l.result_summary = { skipped: "AI features are disabled or no API key set" }
          l.total_rows = 0
          l.save!
          next
        end

        managers = Manager.all.to_a
        l.total_rows = managers.size
        l.save!
        managers.each do |manager|
          l.processed_rows += 1 if Ai::Briefs.manager_weekly(manager).present?
        rescue StandardError => e
          l.error_count += 1
          l.rejected_records_data << { subject: "manager ##{manager.id} #{manager.name}", error: e.message }
        end
        l.save!
      end
    end
  end
end
