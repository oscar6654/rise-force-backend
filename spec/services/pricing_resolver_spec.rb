require "rails_helper"

RSpec.describe PricingResolver do
  let(:version) { create(:pricing_version) }
  let(:gold) { StoreCategory.find_or_create_by_code("gold") }
  let(:mainstream) { ProductTier.find_or_create_by_code("mainstream") }
  let(:product) { create(:product, tier_code: "mainstream", item_cost: 100, case_cost: 100) }

  before do
    version.pricing_rules.create!(store_category: gold, product_tier: mainstream, markup_rate: 0.15)
    version.publish!(nil)
  end

  it "resolves unit price as base * (1 + markup)" do
    resolver = PricingResolver.new
    expect(resolver.markup_rate(gold.id, mainstream.id)).to eq(0.15)
    expect(resolver.price_for(gold, product)).to eq(115.0)
    expect(resolver.price_for("gold", product)).to eq(115.0)
  end

  it "returns nil when no rule exists for the combination" do
    silver = StoreCategory.find_or_create_by_code("silver")
    expect(PricingResolver.new.price_for(silver, product)).to be_nil
  end

  it "uses the latest published version effective on/before today" do
    newer = create(:pricing_version, effective_date: Date.current)
    newer.pricing_rules.create!(store_category: gold, product_tier: mainstream, markup_rate: 0.25)
    newer.publish!(nil)

    expect(PricingResolver.new.price_for(gold, product)).to eq(125.0)
    expect(version.reload).to be_superseded
  end
end
