class OrderBatch < ApplicationRecord
  belongs_to :branch
  belongs_to :seller, optional: true
  belongs_to :locked_by, class_name: "User", optional: true
  belongs_to :downloaded_by, class_name: "User", optional: true
  has_many :orders, dependent: :nullify

  enum :status, { open: 0, locked: 1, downloaded: 2, invoiced: 3, voided: 4 }, default: :open

  scope :for_branches, ->(ids) { where(branch_id: ids) }

  # Build a new batch for (branch, seller) by scooping unbatched submitted
  # orders. Uses FOR UPDATE SKIP LOCKED so concurrent builds don't grab the
  # same orders. Returns the batch (or nil if nothing to batch).
  def self.build_for(branch:, seller:, user:)
    transaction do
      candidates = Order.where(branch: branch, seller: seller, status: :submitted, order_batch_id: nil)
                        .lock("FOR UPDATE SKIP LOCKED")
                        .to_a
      return nil if candidates.empty?

      seq = (where(branch: branch, seller: seller).maximum(:sequence) || 0) + 1
      batch = create!(
        branch: branch, seller: seller, sequence: seq, status: :locked, locked_at: Time.current,
        locked_by: user, batch_number: build_number(branch, seller, seq),
        order_count: candidates.size, total_amount: candidates.sum(&:total_amount)
      )
      Order.where(id: candidates.map(&:id)).update_all(order_batch_id: batch.id, status: Order.statuses[:batched], updated_at: Time.current)
      batch
    end
  end

  # Mark as downloaded and record who/when. Re-download is ALWAYS allowed
  # (OSB may need the CSV again), including after the batch is invoiced. Each
  # call refreshes downloaded_at/by for audit; an INVOICED batch stays invoiced
  # (its orders don't go back into "to invoice"). Row lock keeps concurrent
  # downloads consistent.
  def download!(user)
    self.class.transaction do
      locked = self.class.lock.find(id)         # SELECT ... FOR UPDATE
      if locked.invoiced?
        locked.update!(downloaded_at: Time.current, downloaded_by: user)
      else
        locked.update!(status: :downloaded, downloaded_at: Time.current, downloaded_by: user)
        locked.orders.where(status: %i[submitted batched])
              .update_all(status: Order.statuses[:downloaded], updated_at: Time.current)
      end
      locked
    end
  end

  # Called at the end of a successful vcsi_rise sellout sync (Import Logs).
  # Every batch OSB downloaded BEFORE the sync started has been cut into
  # vcsi_rise, so it and its orders flip to INVOICED — clearing them from the
  # app's "to invoice" and freezing the batch against re-download. Batches
  # downloaded after the sync started wait for the next sync. Returns the
  # number of orders invoiced.
  def self.mark_invoiced_after_sync!(sync_started_at)
    transaction do
      ids = where(status: :downloaded).where(downloaded_at: ..sync_started_at).lock.pluck(:id)
      return 0 if ids.empty?

      now = Time.current
      where(id: ids).update_all(status: statuses[:invoiced], updated_at: now)
      Order.where(order_batch_id: ids, status: :downloaded)
           .update_all(status: Order.statuses[:invoiced], updated_at: now)
    end
  end

  def self.build_number(branch, seller, seq)
    "#{branch.code}-#{seller&.seller_code || 'ALL'}-#{Time.current.strftime('%Y%m%d')}-#{format('%03d', seq)}"
  end
end
