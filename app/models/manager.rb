class Manager < ApplicationRecord
  # App login for a field manager who oversees a set of sellers.
  has_secure_password :pin, validations: false

  belongs_to :branch, optional: true
  has_many :sellers, dependent: :nullify

  enum :status, { active: 0, inactive: 1 }, default: :active

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true

  def pin_set?
    pin_digest.present?
  end

  # Every seller_id this manager's team spans, expanded through login groups so a
  # grouped seller (2 branches) counts once as a team member.
  def team_seller_ids
    roots = sellers.pluck(:id)
    Seller.where("id IN (:r) OR primary_seller_id IN (:r)", r: roots).pluck(:id).uniq
  end
end
