FactoryBot.define do
  factory :branch do
    sequence(:code) { |n| "BR#{n}" }
    name { "Branch" }
  end

  factory :user do
    sequence(:email) { |n| "user#{n}@sfa.local" }
    first_name { "Test" }
    last_name  { "User" }
    password { "password123" }
  end

  factory :channel do
    sequence(:code) { |n| "CH#{n}" }
    name { "Channel" }
  end

  factory :product_tier do
    sequence(:code) { |n| "tier#{n}" }
    name { "Tier" }
  end

  factory :store_category do
    sequence(:code) { |n| "cat#{n}" }
    name { "Category" }
    letter { "A" }
  end

  factory :product do
    sequence(:sku) { |n| "SKU-#{n}" }
    description { "Product" }
    tier_code { "mainstream" } # resolved to a ProductTier master
    item_cost { 100 }
    case_cost { 100 }
  end

  factory :seller do
    branch
    sequence(:seller_code) { |n| "SLR-#{n}" }
    name { "Seller" }
  end

  factory :assortment_type do
    sequence(:code) { |n| "type_#{n}" }
    name { "Type" }
  end

  factory :assortment do
    sequence(:name) { |n| "Assortment #{n}" }
    assortment_type
    status { :active }
  end

  factory :store do
    branch
    sequence(:store_code) { |n| "ST-#{n}" }
    name { "Store" }
    category_code { "gold" } # resolved to a StoreCategory master
    visit_frequency { :f4 }
    week_pattern { :every_week }
    visit_day { :mon }
    visit_sequence { 1 }
  end

  factory :store_registration do
    seller
    branch
    sequence(:client_uuid) { |n| "reg-uuid-#{n}" }
    name { "New Store" }
    proposed_category { nil } # seller picks channel; backend assigns category
  end

  factory :pricing_version do
    name { "V" }
    effective_date { Date.current }
  end

  factory :order do
    seller
    store
    branch
    ordered_at { Time.current }
    client_uuid { SecureRandom.uuid }
  end
end
