# Admin-managed assortment "type" (distribution / initiative / focus / npd, plus
# any the team adds in the console). Replaces the old fixed integer enum, so new
# types need no deploy — add a row and it appears in the assortment form and in
# incentive schemes. `code` is the stable key that scheme configs reference.
class AssortmentType < ApplicationRecord
  has_many :assortments, dependent: :restrict_with_error

  validates :name, presence: true
  validates :code, presence: true, uniqueness: { case_sensitive: false }

  before_validation :normalize_code

  scope :ordered, -> { order(:position, :name) }
  scope :enabled, -> { where(active: true) }

  def to_s = name

  private

  # A stable, referenceable slug (e.g. "Holiday Push" -> "holiday_push").
  def normalize_code
    self.code = code.to_s.strip.parameterize.underscore if code.present?
  end
end
