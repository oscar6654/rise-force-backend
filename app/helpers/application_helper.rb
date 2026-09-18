module ApplicationHelper
  # Sidebar navigation, grouped into sections. Each item is gated by an RBAC
  # (resource, :view) permission so users only see what they can open.
  # Milestones append their modules to the relevant section.
  NavItem = Struct.new(:label, :path, :icon, :resource, keyword_init: true)

  def nav_sections
    sections = {
      "Overview" => [
        NavItem.new(label: "Dashboard", path: root_path, icon: "▤", resource: :dashboard)
      ],
      "Field" => [
        NavItem.new(label: "Approvals", path: store_registrations_path, icon: "✓", resource: :store_registration),
        NavItem.new(label: "Sellers", path: sellers_path, icon: "◍", resource: :seller),
        NavItem.new(label: "Field managers", path: managers_path, icon: "◈", resource: :seller),
        NavItem.new(label: "Route plans", path: routes_path, icon: "⇄", resource: :route_plan),
        NavItem.new(label: "Orders", path: orders_path, icon: "🧾", resource: :order),
        NavItem.new(label: "Batch download", path: order_batches_path, icon: "⭳", resource: :order_batch),
        NavItem.new(label: "Field visits", path: visits_path, icon: "📍", resource: :visit),
        NavItem.new(label: "Assortment compliance", path: compliance_index_path, icon: "☑", resource: :store),
        NavItem.new(label: "Stock & replenishment", path: replenishment_index_path, icon: "📦", resource: :stock_count),
        NavItem.new(label: "Competitor & prices", path: competitor_price_checks_path, icon: "⚖", resource: :competitor_check)
      ],
      "Organization" => [
        NavItem.new(label: "Branch master",    path: branches_path,         icon: "◫", resource: :branch),
        NavItem.new(label: "Warehouse master", path: warehouses_path,       icon: "▤", resource: :warehouse)
      ],
      "Masters" => [
        NavItem.new(label: "Store master",   path: stores_path,           icon: "▦", resource: :store),
        NavItem.new(label: "Channel master", path: channels_path,         icon: "❏", resource: :channel),
        NavItem.new(label: "Product master", path: products_path,         icon: "▣", resource: :product),
        NavItem.new(label: "Channel availability", path: product_channels_path, icon: "❏", resource: :product),
        NavItem.new(label: "Brands",         path: brands_path,           icon: "◆", resource: :brand),
        NavItem.new(label: "Product categories", path: product_categories_path, icon: "≣", resource: :product_category),
        NavItem.new(label: "Product tiers",  path: product_tiers_path,    icon: "≣", resource: :product_tier),
        NavItem.new(label: "Store categories", path: store_categories_path, icon: "≣", resource: :store_category),
        NavItem.new(label: "Assortments",    path: assortments_path,      icon: "☑", resource: :assortment),
        NavItem.new(label: "Pricing master", path: pricing_versions_path, icon: "₱", resource: :pricing),
        NavItem.new(label: "Planograms",     path: planograms_path,       icon: "▥", resource: :planogram),
        NavItem.new(label: "Promos",         path: promos_path,           icon: "%", resource: :promo)
      ],
      "Administration" => [
        NavItem.new(label: "Users", path: admin_users_path, icon: "◉", resource: :user),
        NavItem.new(label: "Roles & permissions", path: admin_roles_path, icon: "⚿", resource: :role),
        NavItem.new(label: "Incentive schemes", path: incentive_schemes_path, icon: "₱", resource: :incentive_scheme),
        NavItem.new(label: "vcsi_rise linking", path: admin_vcsi_linking_path, icon: "⇆", resource: :system_setting),
        NavItem.new(label: "Import logs", path: job_logs_path, icon: "⧉", resource: :job_log),
        NavItem.new(label: "System settings", path: admin_system_settings_path, icon: "⚙", resource: :system_setting)
      ]
    }

    sections.transform_values do |items|
      items.select { |item| can?(item.resource, :view) }
    end.reject { |_section, items| items.empty? }
  end

  def active_nav?(path)
    current_page?(path) || (path != root_path && request.path.start_with?(path))
  end

  def flash_class(level)
    case level.to_s
    when "notice", "success" then "bg-emerald-50 text-emerald-800 border-emerald-200"
    when "alert", "error"    then "bg-red-50 text-red-800 border-red-200"
    else "bg-slate-50 text-slate-700 border-slate-200"
    end
  end

  # A click-to-open ⓘ explainer (pure CSS via <details>, no JS). Inline styles
  # (not Tailwind classes) so it renders regardless of the CSS purge — the helper
  # builds markup in Ruby, which the Tailwind content scanner doesn't see.
  def info_tip(text, align: "left")
    box = [
      "position:absolute", "top:100%", (align == "right" ? "right:0" : "left:0"),
      "margin-top:6px", "width:260px", "max-width:78vw",
      "background:#1e293b", "color:#fff", "font-size:12px", "font-weight:400",
      "line-height:1.5", "padding:10px 12px", "border-radius:10px",
      "box-shadow:0 12px 32px rgba(15,23,42,.35)", "white-space:normal", "z-index:50"
    ].join(";")
    tag.details(style: "display:inline-block;position:relative;vertical-align:middle") do
      concat tag.summary("ⓘ", style: "display:inline-block;list-style:none;cursor:pointer;color:#94a3b8;font-size:13px;line-height:1")
      concat tag.div(text, style: box)
    end
  end
end
