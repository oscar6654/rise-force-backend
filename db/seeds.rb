# frozen_string_literal: true

# Idempotent seed for the SFA backend console. Safe to re-run.

# ---------------------------------------------------------------------------
# 1. Permissions — resource => applicable actions
# ---------------------------------------------------------------------------
RESOURCE_ACTIONS = {
  "dashboard"          => %w[view],
  "branch"             => %w[view create update],
  "warehouse"          => %w[view create update],
  "store"              => %w[view create update destroy],
  "store_registration" => %w[view approve],
  "route_plan"         => %w[view update],
  "channel"            => %w[view create update],
  "product"            => %w[view create update],
  "brand"              => %w[view create update],
  "product_category"   => %w[view create update],
  "product_tier"       => %w[view create update],
  "store_category"     => %w[view create update],
  "assortment"         => %w[view create update],
  "pricing"            => %w[view create update publish],
  "planogram"          => %w[view create update publish],
  "promo"              => %w[view create update publish],
  "seller"             => %w[view create update],
  "order"              => %w[view],
  "order_batch"        => %w[view download],
  "visit"              => %w[view download],
  "sync"               => %w[sync],
  "user"               => %w[view create update],
  "role"               => %w[view create update],
  "system_setting"     => %w[view update],
  "job_log"            => %w[view],
  "incentive_scheme"   => %w[view create update],
  "stock_count"        => %w[view download],       # in-store shelf audits (field capture)
  "competitor_check"   => %w[view download]        # shelf price + competitor capture
}.freeze

RESOURCE_ACTIONS.each do |resource, actions|
  actions.each do |action|
    Permission.find_or_create_by!(resource: resource, action: action)
  end
end
puts "Permissions: #{Permission.count}"

# ---------------------------------------------------------------------------
# 2. Roles + grants
# ---------------------------------------------------------------------------
def grant(role, resource, actions)
  Array(actions).each do |action|
    perm = Permission.find_by(resource: resource, action: action)
    next unless perm

    RolePermission.find_or_create_by!(role: role, permission: perm)
  end
end

def grant_all(role)
  RESOURCE_ACTIONS.each { |resource, actions| grant(role, resource, actions) }
end

roles = {}
{
  "superadmin"       => "Full system access",
  "national_manager" => "National operations: masters, publishing, approvals, sync",
  "branch_manager"   => "Branch-scoped operations and approvals",
  "merchandiser"     => "Product, pricing, planogram and promo management",
  "osb_operator"     => "Backroom: order review and batch download",
  "viewer"           => "Read-only access"
}.each do |name, desc|
  roles[name] = Role.find_or_create_by!(name: name) { |r| r.description = desc }
end

# superadmin — everything
grant_all(roles["superadmin"])

# viewer — view on every resource that has a :view action
RESOURCE_ACTIONS.each_key { |resource| grant(roles["viewer"], resource, "view") }

# national_manager
nm = roles["national_manager"]
RESOURCE_ACTIONS.each_key { |resource| grant(nm, resource, "view") }
%w[branch warehouse store channel product brand product_category product_tier store_category assortment seller route_plan].each { |r| grant(nm, r, %w[create update]) }
grant(nm, "store", "destroy")
%w[pricing planogram promo].each { |r| grant(nm, r, %w[create update publish]) }
grant(nm, "store_registration", "approve")
grant(nm, "order_batch", "download")
grant(nm, "sync", "sync")
grant(nm, "incentive_scheme", %w[create update])
%w[stock_count competitor_check visit].each { |r| grant(nm, r, "download") }

# branch_manager (branch-scoped at the controller layer)
bm = roles["branch_manager"]
%w[dashboard store store_registration route_plan seller order order_batch visit].each { |r| grant(bm, r, "view") }
grant(bm, "store", %w[create update])
grant(bm, "seller", %w[create update])
grant(bm, "route_plan", "update")
grant(bm, "store_registration", "approve")
grant(bm, "order_batch", "download")
%w[stock_count competitor_check].each { |r| grant(bm, r, %w[view download]) }
grant(bm, "visit", "download") # bm already has visit:view above

# merchandiser
md = roles["merchandiser"]
grant(md, "dashboard", "view")
grant(md, "store", "view")
%w[channel product brand product_category product_tier store_category assortment].each { |r| grant(md, r, %w[view create update]) }

# Assortment types (admin-managed lookup; the original fixed set). Idempotent so
# a schema-load + seed on a fresh DB has them even without running the migration.
[%w[distribution Distribution], %w[initiative Initiative], %w[focus Focus], %w[npd NPD]].each_with_index do |(code, name), i|
  AssortmentType.find_or_create_by!(code: code) { |t| t.name = name; t.position = i; t.active = true }
end
%w[pricing planogram promo].each { |r| grant(md, r, %w[view create update publish]) }
grant(md, "incentive_scheme", %w[view create update])

# osb_operator (branch-scoped)
osb = roles["osb_operator"]
grant(osb, "dashboard", "view")
grant(osb, "order", "view")
grant(osb, "order_batch", %w[view download])

puts "Roles: #{Role.count}, RolePermissions: #{RolePermission.count}"

# ---------------------------------------------------------------------------
# 3. Sample branch
# ---------------------------------------------------------------------------
Branch.find_or_create_by!(code: "HQ") do |b|
  b.name = "Head Office"
  b.region = "NCR"
  b.timezone = "Asia/Manila"
end
puts "Branches: #{Branch.count}"

# ---------------------------------------------------------------------------
# 3b. Channels, brands, product categories
# ---------------------------------------------------------------------------
[
  ["SARI", "Sari-Sari Store", "Neighborhood micro-retail"],
  ["MINI", "Mini-Mart", "Small self-service grocery"],
  ["GROC", "Groceries", "Mid-size grocery"],
  ["CARIN", "Carinderia", "Eatery / food stall"]
].each do |code, name, desc|
  Channel.find_or_create_by!(code: code) { |c| c.name = name; c.description = desc }
end

[["NEST", "Nestle"], ["URC", "Universal Robina"], ["PGC", "P&G"]].each_with_index do |(code, name), i|
  Brand.find_or_create_by!(code: code) { |b| b.name = name; b.sort_order = i }
end

[["BEV", "Beverages"], ["SNACK", "Snacks"], ["HOME", "Home Care"]].each do |code, name|
  ProductCategory.find_or_create_by!(code: code) { |pc| pc.name = name }
end
puts "Channels: #{Channel.count}, Brands: #{Brand.count}, Categories: #{ProductCategory.count}"

# ---------------------------------------------------------------------------
# 4. Admin user (password from ENV, default for local dev)
# ---------------------------------------------------------------------------
admin_email = ENV.fetch("ADMIN_EMAIL", "admin@sfa.local")
admin_password = ENV.fetch("ADMIN_PASSWORD", "password123")

admin = User.find_or_initialize_by(email: admin_email)
if admin.new_record?
  admin.assign_attributes(
    first_name: "System",
    last_name: "Administrator",
    password: admin_password,
    password_confirmation: admin_password,
    branch_id: nil # global access
  )
  admin.save!
end
admin.assign_role("superadmin")
puts "Admin user: #{admin.email} (roles: #{admin.role_names.join(', ')})"

# ---------------------------------------------------------------------------
# 4b. Pricing version 1 (published) with all 12 category x tier rules
# ---------------------------------------------------------------------------
# Flexible tier/category masters are seeded by the migration; ensure they exist.
ProductTier.find_or_create_by_code("premium", name: "Tier 1 — Premium")
ProductTier.find_or_create_by_code("mainstream", name: "Tier 2 — Mainstream")
ProductTier.find_or_create_by_code("value", name: "Tier 3 — Value")
%w[platinum gold silver bronze].each_with_index do |code, i|
  sc = StoreCategory.find_or_create_by_code(code)
  sc.update!(letter: %w[A B C D][i], sort_order: i + 1)
end

if PricingVersion.none?
  pv = PricingVersion.create!(name: "Initial matrix", effective_date: Date.current, status: :draft)
  markups = {
    "platinum" => { "premium" => 0.08, "mainstream" => 0.10, "value" => 0.12 },
    "gold"     => { "premium" => 0.10, "mainstream" => 0.12, "value" => 0.14 },
    "silver"   => { "premium" => 0.12, "mainstream" => 0.15, "value" => 0.18 },
    "bronze"   => { "premium" => 0.15, "mainstream" => 0.18, "value" => 0.22 }
  }
  markups.each do |cat_code, tiers|
    cat = StoreCategory.find_by(code: cat_code)
    tiers.each do |tier_code, rate|
      pv.pricing_rules.create!(store_category: cat, product_tier: ProductTier.find_by(code: tier_code), markup_rate: rate)
    end
  end
  pv.publish!(admin)
  puts "PricingVersion v#{pv.version_number} published with #{pv.pricing_rules.count} rules"
end

# ---------------------------------------------------------------------------
# 5. System settings (mailer, AWS S3, CloudFront, vcsi_rise, URLs, features)
# ---------------------------------------------------------------------------
def seed_setting(key, value:, category:, description:, type: "string", encrypted: false, required: false)
  return if SystemSetting.exists?(key: key)

  SystemSetting.create!(
    key: key, value: value.to_s, value_type: type, category: category,
    description: description, encrypted: encrypted, required: required,
    test_status: "untested"
  )
end

# email — choose Mailgun API or an SMTP server (or auto: Mailgun if configured)
seed_setting("email_provider",      value: "auto", category: "email", description: "Delivery method: auto (Mailgun if configured, else SMTP), mailgun, or smtp")
seed_setting("mailgun_api_key",     value: "", category: "email", description: "Mailgun API key (used when delivery method is Mailgun)", encrypted: true)
seed_setting("mailgun_domain",      value: "", category: "email", description: "Mailgun sending domain")
seed_setting("smtp_address",        value: "", category: "email", description: "SMTP server host (fallback if Mailgun unset)")
seed_setting("smtp_port",           value: "587", type: "integer", category: "email", description: "SMTP port")
seed_setting("smtp_domain",         value: "", category: "email", description: "HELO domain")
seed_setting("smtp_user_name",      value: "", category: "email", description: "SMTP username")
seed_setting("smtp_password",       value: "", category: "email", description: "SMTP password", encrypted: true)
seed_setting("smtp_authentication", value: "plain", category: "email", description: "plain / login / cram_md5")
seed_setting("smtp_starttls",       value: "true", type: "boolean", category: "email", description: "Use STARTTLS")
seed_setting("email_from",          value: "no-reply@sfa.local", category: "email", description: "Default From address")

# AWS S3
seed_setting("aws_access_key_id",     value: "", category: "aws", description: "S3 access key", encrypted: true)
seed_setting("aws_secret_access_key", value: "", category: "aws", description: "S3 secret key", encrypted: true)
seed_setting("aws_region",            value: "ap-southeast-1", category: "aws", description: "S3 region")
seed_setting("aws_bucket",            value: "", category: "aws", description: "S3 bucket name")

# CloudFront CDN
seed_setting("cloudfront_host",       value: "", category: "cdn", description: "CloudFront distribution domain (fronts S3, unsigned URLs)")
seed_setting("cloudfront_thumbnails", value: "false", type: "boolean", category: "cdn", description: "Serve resized variants via CloudFront (after backfilling variants)")

# vcsi_rise API
seed_setting("vcsi_rise_base_url",  value: "", category: "vcsi", description: "vcsi_rise API base URL (actual sellout/stock/targets)")
seed_setting("vcsi_rise_api_token", value: "", category: "vcsi", description: "vcsi_rise API bearer token", encrypted: true)
# Store target derivation (vcsi_rise carries store history, SFA derives the target)
seed_setting("store_target_months",      value: "3",    type: "integer", category: "vcsi", description: "Trailing months of vcsi_rise sellout averaged to derive a store target")
seed_setting("store_target_growth_rate", value: "0.05", type: "decimal", category: "vcsi", description: "Growth uplift on the trailing average (0.05 = +5%)")
seed_setting("seller_pull_throttle_seconds", value: "300", type: "integer", category: "vcsi", description: "Min seconds between a seller's on-demand vcsi_rise pulls from the app")
# Endpoint path overrides (defaults match the vcsi_rise routes; change only if vcsi_rise moves them)
seed_setting("vcsi_store_sellout_path", value: "/api/v1/sfa/store_sellout", category: "vcsi", description: "vcsi_rise per-store actual sellout endpoint")
seed_setting("vcsi_store_history_path", value: "/api/v1/sfa/store_history", category: "vcsi", description: "vcsi_rise per-store monthly history endpoint")
seed_setting("vcsi_stores_path",        value: "/api/v1/sfa/stores",        category: "vcsi", description: "vcsi_rise customer master feed (store link validation)")

# URLs / app
seed_setting("app_host",     value: "localhost:3000", category: "urls", description: "Public host for mailer links")
seed_setting("app_protocol", value: "http", category: "urls", description: "http / https")

# company / branding
seed_setting("company_name", value: "Distribution Inc.", category: "company", description: "Distributor name shown in the console")
seed_setting("app_name",     value: "SFA Console", category: "branding", description: "Application display name")

# mobile app — check-in geofence (how strictly the app enforces being at the store)
seed_setting("checkin_geofence_mode",     value: "soft", category: "mobile", description: "Check-in location rule — warn (record distance only), soft (require a logged reason when far), or hard (block beyond the radius)")
seed_setting("checkin_geofence_radius_m", value: "150", type: "integer", category: "mobile", description: "How many metres from the store's pin still counts as “at the store” for check-in")

# store enrollment — sellers pick the channel; the backend assigns this default
# category so a new store can sell immediately (a reviewer reassigns it later).
seed_setting("default_enrollment_category", value: "silver", category: "stores", description: "StoreCategory code a newly enrolled store starts on (sets its price list until a reviewer reassigns it)")
seed_setting("provisional_code_prefix", value: "PROV", category: "stores", description: "Prefix for provisional store codes generated at enrollment")

# feature flags
seed_setting("feature_gps_mismatch_warn_meters", value: "150", type: "integer", category: "features", description: "Warn when check-in GPS is farther than this from the store")

puts "SystemSettings: #{SystemSetting.count}"
puts "Seed complete."
