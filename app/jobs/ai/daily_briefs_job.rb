module Ai
  # Precomputes the day's AI assist text for every active seller (game plan) and
  # manager (digest). TRIGGERED MANUALLY from Import Logs (not scheduled) so the
  # operator runs it AFTER the vcsi_rise sellout sync, guaranteeing fresh data.
  # Logs to JobLog so progress/errors show on the Logs page. No-op unless AI is
  # enabled + keyed. Per-subject failures are isolated.
  class DailyBriefsJob < ApplicationJob
    queue_as :default

    def perform(user: nil, log: nil)
      JobLog.track(:ai_daily_briefs, user: user, log: log) do |l|
        unless Ai::Anthropic.enabled?
          l.result_summary = { skipped: "AI features are disabled or no API key set" }
          l.total_rows = 0
          l.save!
          next
        end

        sellers  = Seller.active.where(primary_seller_id: nil).to_a
        managers = Manager.all.to_a
        l.total_rows = sellers.size + managers.size
        l.save!

        done = 0
        sellers.each do |seller|
          l.processed_rows += 1 if Ai::Briefs.seller_plan(seller).present?
        rescue StandardError => e
          l.error_count += 1
          l.rejected_records_data << { subject: "seller ##{seller.id} #{seller.name}", error: e.message }
        ensure
          done += 1
          l.save! if (done % 5).zero? # live progress on the Import Logs page
        end

        managers.each do |manager|
          l.processed_rows += 1 if Ai::Briefs.manager_digest(manager).present?
        rescue StandardError => e
          l.error_count += 1
          l.rejected_records_data << { subject: "manager ##{manager.id} #{manager.name}", error: e.message }
        ensure
          done += 1
          l.save! if (done % 5).zero?
        end

        l.save!
      end
    end
  end
end
