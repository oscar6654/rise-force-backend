class ProductCategory < ApplicationRecord
  enum :status, { active: 0, inactive: 1 }, default: :active

  has_many :products, dependent: :restrict_with_error

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true

  scope :ordered, -> { order(:name) }
  scope :active, -> { where(status: :active) }

  def self.find_or_create_by_name(name)
    return nil if name.blank?

    clean = name.to_s.strip
    where("lower(name) = ?", clean.downcase).first || create!(name: clean, code: unique_code(clean))
  end

  def self.unique_code(name)
    base = name.parameterize(separator: "_").upcase.first(24).presence || "CAT"
    code = base
    code = "#{base}_#{SecureRandom.hex(2).upcase}" while exists?(code: code)
    code
  end
end
