# frozen_string_literal: true

# Applies DB-backed SMTP + URL settings to ActionMailer at boot. Guarded so
# the app boots even before the system_settings table exists. Changes to these
# settings take effect on the next restart (matches the vcsi_rise behaviour
# surfaced in the admin UI copy).
Rails.application.config.after_initialize do
  next unless ActiveRecord::Base.connection.table_exists?("system_settings")

  host     = SystemSetting.get("app_host", "localhost:3000")
  protocol = SystemSetting.get("app_protocol", Rails.env.production? ? "https" : "http")

  ActionMailer::Base.default_url_options = { host: host, protocol: protocol }

  # Delivery method: explicit choice wins; "auto" prefers Mailgun when configured.
  provider = SystemSetting.get("email_provider", "auto").to_s
  mailgun_ready = SystemSetting.get("mailgun_api_key").present? && SystemSetting.get("mailgun_domain").present?
  use_mailgun = provider == "mailgun" || (provider == "auto" && mailgun_ready)

  if use_mailgun
    ActionMailer::Base.delivery_method = :mailgun
  elsif provider == "smtp" || SystemSetting.get("smtp_address").present?
    ActionMailer::Base.delivery_method = :smtp
    ActionMailer::Base.smtp_settings = {
      address:              SystemSetting.get("smtp_address"),
      port:                 SystemSetting.get("smtp_port", 587).to_i,
      domain:               SystemSetting.get("smtp_domain"),
      user_name:            SystemSetting.get("smtp_user_name"),
      password:             SystemSetting.get("smtp_password"),
      authentication:       SystemSetting.get("smtp_authentication", "plain"),
      enable_starttls_auto: SystemSetting.get("smtp_starttls", true)
    }.compact
  end
rescue StandardError => e
  Rails.logger.debug { "Could not apply mailer settings from database: #{e.message}" }
end
