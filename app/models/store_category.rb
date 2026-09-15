class StoreCategory < ApplicationRecord
  has_many :stores, dependent: :restrict_with_error
  has_many :pricing_rules, dependent: :destroy

  validates :code, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:sort_order, :name) }

  def label
    letter.present? ? "#{letter} — #{name}" : name
  end

  # Resolve a free-typed category to a single record. Match any existing
  # category whose code normalizes the same way (lower + spaces→underscores),
  # so "Category 03", "category_03" and "CATEGORY 03" all resolve to ONE row
  # instead of spawning duplicates that split stores from their pricing rules.
  def self.find_or_create_by_code(code, name: nil)
    return nil if code.blank?

    normalized = code.to_s.strip.downcase.gsub(/\s+/, "_")
    existing = where("lower(regexp_replace(btrim(code), '\\s+', '_', 'g')) = ?", normalized).first
    return existing if existing

    create!(code: normalized, name: name.presence || code.to_s.titleize,
            sort_order: (maximum(:sort_order) || 0) + 1)
  end
end
