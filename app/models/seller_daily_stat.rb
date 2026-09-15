# Daily rollup of a seller's route completion, used to power streaks / daily
# goal tracking on the app. One row per seller per day, upserted by
# Api::V1::MeController#summary (which the app calls on every sync). The day's
# "goal" is completing the planned route: visiting every store due that day.
#
# Streaks are computed over the SEQUENCE of working-day rows (planned > 0), so
# weekends / rest days (no planned stores) never break a streak — only failing
# to finish a day you were scheduled to work does.
class SellerDailyStat < ApplicationRecord
  belongs_to :seller

  scope :working_days, -> { where("planned > 0") }

  # Upsert today's rollup and return the record.
  def self.record_day!(seller, date, planned:, visited:, productive_calls:, orders_count:)
    rec = find_or_initialize_by(seller_id: seller.id, stat_date: date)
    rec.assign_attributes(
      planned: planned, visited: visited,
      productive_calls: productive_calls, orders_count: orders_count,
      goal_met: planned.positive? && visited >= planned
    )
    rec.save!
    rec
  end

  # { current:, best: } over working-day rows. `today` counts toward the current
  # streak only once its goal is met, so an in-progress day reads as "0 today"
  # without breaking a run built on prior days.
  def self.streak_stats(seller, today: Date.current)
    rows = working_days.where(seller_id: seller.id).order(:stat_date).to_a

    best = run = 0
    rows.each do |r|
      run = r.goal_met ? run + 1 : 0
      best = run if run > best
    end

    current = 0
    rows.reverse_each do |r|
      next if r.stat_date == today && !r.goal_met # today still in progress
      break unless r.goal_met

      current += 1
    end

    { current: current, best: best }
  end
end
