class JobLog < ApplicationRecord
  belongs_to :triggered_by, class_name: "User", optional: true
  has_one_attached :source_file

  enum :job_type, {
    store_import: 0, product_import: 1, channel_import: 2, pricing_publish: 3,
    sellout_sync: 4, stock_sync: 5, target_sync: 6, order_batch_export: 7,
    planned_visit_generation: 8, store_sellout_sync: 9, store_target_compute: 10,
    product_channel_import: 11, promo_import: 12, store_sku_sellout_sync: 13
  }
  enum :status, { pending: 0, running: 1, completed: 2, failed: 3, partial: 4 }, default: :pending

  scope :recent, -> { order(created_at: :desc) }

  # Convenience wrapper for import/sync jobs: marks running, yields the log,
  # captures failure, and stamps timing. Pass an existing `log:` (e.g. one
  # created by the controller and enqueued to a background job) to run against
  # it instead of creating a fresh one.
  def self.track(job_type, user: nil, filename: nil, log: nil)
    log ||= create!(job_type: job_type, triggered_by: user, filename: filename)
    log.update!(status: :running, started_at: Time.current)
    yield log
    log.update!(status: log.error_count.positive? ? :partial : :completed, finished_at: Time.current)
    log
  rescue StandardError => e
    log&.update(status: :failed, finished_at: Time.current,
                result_summary: { error: e.message })
    raise
  end
end
