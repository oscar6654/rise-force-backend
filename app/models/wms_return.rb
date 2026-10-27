class WmsReturn < ApplicationRecord
  belongs_to :warehouse
  belongs_to :store, optional: true
  has_many :wms_return_lines, dependent: :destroy

  enum :source, { upload: 0, manual: 1 }, default: :upload
  enum :status, { open: 0, processing: 1, closed: 2 }, default: :open

  validates :ref, presence: true, uniqueness: { scope: :warehouse_id, case_sensitive: false }

  def refresh_status!
    update!(status: wms_return_lines.where(status: :pending).exists? ? :processing : :closed) if wms_return_lines.any?
  end
end
