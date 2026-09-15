class Channel < ApplicationRecord
  enum :status, { active: 0, inactive: 1 }, default: :active

  has_many :stores, dependent: :nullify
  has_many :planograms, dependent: :destroy

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
end
