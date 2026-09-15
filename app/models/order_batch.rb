class OrderBatch < ApplicationRecord
  belongs_to :branch
  belongs_to :seller, optional: true
  belongs_to :locked_by, class_name: "User", optional: true
  belongs_to :downloaded_by, class_name: "User", optional: true
  has_many :orders, dependent: :nullify

  enum :status, { open: 0, locked: 1, downloaded: 2, invoiced: 3, voided: 4 }, default: :open

  scope :for_branches, ->(ids) { where(branch_id: ids) }

  class AlreadyDownloaded < StandardError; end

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
      Order.where(id: candidates.map(&:id)).update_all(order_batch_id: batch.id, status: Order.statuses[:batched])
      batch
    end
  end

  # Mark as downloaded exactly once. Row lock + state guard prevents two OSB
  # users double-downloading (and thus double-invoicing).
  def download!(user)
    self.class.transaction do
      locked = self.class.lock.find(id)         # SELECT ... FOR UPDATE
      raise AlreadyDownloaded if locked.downloaded? || locked.invoiced?

      locked.update!(status: :downloaded, downloaded_at: Time.current, downloaded_by: user)
      locked.orders.update_all(status: Order.statuses[:downloaded])
      locked
    end
  end

  def self.build_number(branch, seller, seq)
    "#{branch.code}-#{seller&.seller_code || 'ALL'}-#{Time.current.strftime('%Y%m%d')}-#{format('%03d', seq)}"
  end
end
