class Product < ApplicationRecord
  belongs_to :brand, optional: true
  belongs_to :product_category, optional: true
  belongs_to :product_tier, optional: true # flexible, managed master (drives pricing)
  has_many :assortment_items, dependent: :destroy
  has_many :product_channels, dependent: :destroy
  has_many :channels, through: :product_channels
  has_one_attached :photo

  # item_tier is the tiering (create-or-pick, drives the pricing matrix).
  attr_writer :tier_code, :brand_name, :category_name

  enum :status, { active: 0, discontinued: 1 }, default: :active

  before_validation :resolve_tier_code, :resolve_brand_name, :resolve_category_name

  validates :sku, presence: true, uniqueness: { case_sensitive: false }
  validates :description, presence: true
  validates :item_cost, :case_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Pre-generate gallery variants so CloudFront can serve them by key.
  GALLERY_VARIANT_LIMITS = [[80, 80], [400, 400]].freeze
  after_commit :generate_photo_variants, on: [:create, :update], if: -> { photo.attached? }

  # Searchable by item key, description and barcodes (IT/CS/SW).
  scope :search, ->(q) {
    return all if q.blank?

    like = "%#{sanitize_sql_like(q)}%"
    where("sku ILIKE :q OR description ILIKE :q OR desc2 ILIKE :q OR " \
          "it_barcode ILIKE :q OR cs_barcode ILIKE :q OR sw_barcode ILIKE :q", q: like)
  }

  # Label used in pickers — includes barcode so it can be searched by it.
  def picker_label
    parts = [description]
    parts << "· #{it_barcode}" if it_barcode.present?
    parts << "(#{sku})"
    parts.join(" ")
  end

  scope :with_barcode, -> { where.not(it_barcode: [nil, ""]) }

  # Products a store on this channel may order. Channel-centric: once a channel
  # has a curated list (≥1 mapping), ONLY those SKUs show for it. A channel with
  # no list yet is "unconfigured" and falls back to all SKUs, so nothing breaks
  # before the mapping is uploaded. Blank channel = no restriction.
  scope :available_in_channel, ->(channel_id) {
    return all if channel_id.blank?
    return all unless ProductChannel.where(channel_id: channel_id).exists? # unconfigured channel

    joins(:product_channels).where(product_channels: { channel_id: channel_id }).distinct
  }

  # Distinct IT barcodes for barcode-grouped pickers (promos, assortments):
  # one option per barcode with a representative label + how many item_keys share it.
  # => [["Coffee 3in1 · 480011… (3 SKUs)", "480011…"], ...]
  def self.barcode_options
    active.with_barcode.order(:description).group_by(&:it_barcode).map do |barcode, prods|
      rep = prods.first
      count = prods.size
      label = "#{rep.description} · #{barcode}"
      label += " (#{count} SKUs)" if count > 1
      [label, barcode]
    end.sort_by(&:first)
  end

  # One representative product per it_barcode for barcode-collapsed catalogs:
  # the active SKU with the highest case_cost (tie: item_cost, then sku). Since
  # item_keys sharing a barcode share a tier, highest cost = highest price, so
  # ordering the representative never undercharges. => { "<barcode>" => id }.
  def self.barcode_representative_ids
    active.where.not(it_barcode: [nil, ""])
          .order(Arel.sql("it_barcode, case_cost DESC NULLS LAST, item_cost DESC NULLS LAST, sku ASC"))
          .pluck(:it_barcode, :id)
          .each_with_object({}) { |(bc, id), h| h[bc] ||= id } # first per barcode = highest cost
  end

  # The catalog-visible representative SKU for a single barcode (highest
  # case_cost active) — so prefill/promo lookups resolve to the SKU the seller
  # actually sees and orders in the collapsed catalog.
  def self.representative_for(barcode)
    return nil if barcode.blank?

    active.where(it_barcode: barcode)
          .order(Arel.sql("case_cost DESC NULLS LAST, item_cost DESC NULLS LAST, sku ASC")).first
  end

  # Union of channel_ids across every item_key sharing a barcode, so collapsing
  # to one representative never hides a barcode from a channel a sibling maps to.
  # => { "<barcode>" => [channel_id, ...] }.
  def self.channel_ids_by_barcode
    ProductChannel.joins(:product).where.not(products: { it_barcode: [nil, ""] })
                  .pluck(Arel.sql("products.it_barcode"), :channel_id)
                  .group_by(&:first).transform_values { |rows| rows.map(&:last).uniq }
  end

  def tier
    product_tier&.code
  end

  def tier_label
    product_tier&.name
  end

  def generate_photo_variants!
    return unless photo.attached?

    GALLERY_VARIANT_LIMITS.each { |limit| photo.variant(resize_to_limit: limit).processed }
  end

  private

  def resolve_tier_code
    return if @tier_code.blank?

    self.product_tier = ProductTier.find_or_create_by_code(@tier_code)
  end

  def resolve_brand_name
    return if @brand_name.nil?

    self.brand = @brand_name.blank? ? nil : Brand.find_or_create_by_name(@brand_name)
  end

  def resolve_category_name
    return if @category_name.nil?

    self.product_category = @category_name.blank? ? nil : ProductCategory.find_or_create_by_name(@category_name)
  end

  def generate_photo_variants
    generate_photo_variants!
  rescue StandardError => e
    Rails.logger.warn "Product #{id}: variant generation failed — #{e.message}"
  end
end
