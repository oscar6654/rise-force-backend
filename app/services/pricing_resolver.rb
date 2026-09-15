# Resolves a store's selling price for a product from the markup matrix:
#   unit_price = cost * (1 + markup_rate)
# where cost is the product's item_cost (per piece) or case_cost (per case).
# Looks up the rule for (store_category, product_tier) in a pricing version
# (defaults to the currently-effective published version). Store categories and
# product tiers are flexible masters, so the matrix is keyed by their ids.
class PricingResolver
  attr_reader :version

  def initialize(version = nil, on: Date.current)
    @version = version || PricingVersion.current(on: on)
    @matrix = nil
  end

  def version_number
    version&.version_number
  end

  # store_category: a StoreCategory, its code, or nil. product: a Product.
  # uom: :pc (item_cost) or :case (case_cost). Returns nil if no rule/cost.
  def price_for(store_category, product, uom: :pc)
    rate = markup_rate(category_id(store_category), product.product_tier_id)
    return nil if rate.nil?

    cost = cost_for(product, uom)
    return nil if cost.nil?

    (cost * (1 + rate)).round(2)
  end

  # The cost basis the markup applies to.
  def cost_for(product, uom = :pc)
    uom.to_s == "case" || uom.to_s == "case_uom" ? product.case_cost : product.item_cost
  end

  def markup_rate(store_category_id, product_tier_id)
    matrix[[store_category_id, product_tier_id]]
  end

  private

  def category_id(store_category)
    return store_category.id if store_category.is_a?(StoreCategory)
    return store_category if store_category.is_a?(Integer)

    StoreCategory.find_by(code: store_category.to_s)&.id
  end

  def matrix
    @matrix ||= begin
      return {} if version.nil?

      version.pricing_rules.each_with_object({}) do |rule, h|
        h[[rule.store_category_id, rule.product_tier_id]] = rule.markup_rate
      end
    end
  end
end
