module Visits
  # Closes visits left "in progress". Two cases:
  #   1. Past-day open visits — the seller never checked out; auto-close them.
  #   2. Same-day duplicates for one (seller, store, day) — keep the richest one
  #      (has stock counts / an order, else the latest) and close the rest.
  # Enforces "one store → one visit" so the Field Visits report stays clean.
  # Idempotent: a visit already closed is skipped.
  class Housekeeping
    def self.close_stale!(before: Date.current.beginning_of_day)
      new(before: before).run
    end

    def initialize(before:)
      @before = before
    end

    # Returns the number of visits auto-closed.
    def run
      closed = 0
      closed += close_past_day_open
      closed += dedup_same_day
      closed
    end

    private

    def close_past_day_open
      count = 0
      Visit.where(status: :in_progress).where("started_at < ?", @before).find_each do |v|
        auto_close!(v)
        count += 1
      end
      count
    end

    def dedup_same_day
      count = 0
      Visit.where(status: :in_progress)
           .includes(:stock_counts, :order)
           .group_by { |v| [v.seller_id, v.store_id, v.visit_date] }
           .each_value do |group|
        next if group.size < 2

        keeper = richest(group)
        (group - [keeper]).each do |v|
          auto_close!(v)
          count += 1
        end
      end
      count
    end

    # The visit worth keeping: most stock counts, an order counts a lot, then newest.
    def richest(group)
      group.max_by do |v|
        [v.stock_counts.size + (v.order ? 1_000 : 0), (v.started_at || v.created_at).to_i]
      end
    end

    def auto_close!(visit)
      has_order = visit.order.present?
      visit.update!(
        status: has_order ? :closed_with_order : :closed_no_order,
        no_order_reason: has_order ? visit.no_order_reason : (visit.no_order_reason.presence || "Auto-closed — not checked out"),
        ended_at: visit.ended_at || visit.started_at || Time.current
      )
    end
  end
end
