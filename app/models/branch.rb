class Branch < ApplicationRecord
  enum :status, { active: 0, inactive: 1 }, default: :active

  has_many :users, dependent: :nullify
  has_many :sellers, dependent: :restrict_with_error
  has_many :routes, dependent: :restrict_with_error
  has_many :stores, dependent: :restrict_with_error
  has_many :store_registrations, dependent: :nullify

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true

  def display_timezone
    timezone.presence || "Asia/Manila"
  end
end
