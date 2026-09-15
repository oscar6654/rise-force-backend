class Route < ApplicationRecord
  belongs_to :seller, optional: true
  belongs_to :branch
  has_many :stores, dependent: :nullify

  enum :status, { active: 0, inactive: 1 }, default: :active

  validates :code, presence: true, uniqueness: { scope: :branch_id, case_sensitive: false }

  def display_name
    [code, name].compact.join(" · ")
  end
end
