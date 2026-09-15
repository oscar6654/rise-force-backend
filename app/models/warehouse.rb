class Warehouse < ApplicationRecord
  belongs_to :branch, optional: true

  enum :status, { active: 0, inactive: 1 }, default: :active

  validates :whs_code, presence: true, uniqueness: { case_sensitive: false }
  validates :wh_name, presence: true
end
