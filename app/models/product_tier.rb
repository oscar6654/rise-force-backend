class ProductTier < ApplicationRecord
  has_many :products, dependent: :restrict_with_error
  has_many :pricing_rules, dependent: :destroy

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:sort_order, :name) }

  # Find an existing tier or create one from a free-typed code (create-or-pick).
  # Match any existing tier whose code normalizes the same way (lower +
  # spaces→underscores) so "H"/"h", and "Tier K"/"tier_k" resolve to ONE row —
  # an exact-match find would miss it and fail to create a variant duplicate
  # ("Code has already been taken").
  def self.find_or_create_by_code(code, name: nil)
    return nil if code.blank?

    normalized = code.to_s.strip.downcase.gsub(/\s+/, "_")
    existing = where("lower(regexp_replace(btrim(code), '\\s+', '_', 'g')) = ?", normalized).first
    return existing if existing

    create!(code: normalized, name: name.presence || code.to_s.titleize,
            sort_order: (maximum(:sort_order) || 0) + 1)
  end
end
