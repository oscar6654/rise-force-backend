class VisitPhoto < ApplicationRecord
  belongs_to :visit
  belongs_to :planogram, optional: true
  has_one_attached :image

  enum :kind, { planogram_compliance: 0, storefront: 1, other: 2 }, prefix: :kind

  validates :client_uuid, presence: true, uniqueness: true
end
