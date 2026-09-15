class Planogram < ApplicationRecord
  belongs_to :channel
  belongs_to :uploaded_by, class_name: "User", optional: true
  has_one_attached :file

  enum :status, { draft: 0, active: 1, archived: 2 }, default: :draft

  validates :title, presence: true

  def image?
    file.attached? && file.content_type.to_s.start_with?("image/")
  end
end
