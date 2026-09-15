# frozen_string_literal: true

# DB-backed application settings (mailer/SMTP, AWS S3, CloudFront, vcsi_rise
# API credentials, feature flags). Editable from the admin UI so credentials
# are not baked into deploys. Mirrors the vcsi_rise SystemSetting pattern:
# a 5-minute in-memory cache, typed values, and category grouping.
class SystemSetting < ApplicationRecord
  # Optional white-label logo, persisted in Active Storage.
  has_one_attached :logo_image

  CATEGORIES = %w[
    branding company email aws cdn vcsi urls certificates features maps general
  ].freeze

  VALUE_TYPES = %w[string integer decimal boolean json].freeze
  TEST_STATUSES = %w[untested success failed].freeze

  # Keys that render as a labelled dropdown (value => human label) instead of a
  # free-text box, so operators can't mistype an enum (e.g. the geofence mode).
  SELECT_OPTIONS = {
    "email_provider" => { "auto" => "Auto (Mailgun if configured, else SMTP)", "mailgun" => "Mailgun API", "smtp" => "SMTP server" },
    "smtp_authentication" => { "plain" => "plain", "login" => "login", "cram_md5" => "cram_md5" },
    # Values must match what the seller app understands (soft / warn / hard).
    "checkin_geofence_mode" => {
      "warn" => "Lenient — allow check-in, just record the distance",
      "soft" => "Require a reason — allow, but the seller must log why they're far",
      "hard" => "Enforce — block check-in beyond the radius"
    }
  }.freeze

  validates :key, presence: true, uniqueness: true
  validates :value_type, inclusion: { in: VALUE_TYPES }
  validates :test_status, inclusion: { in: TEST_STATUSES }, allow_nil: true

  scope :by_category, ->(category) { where(category: category) }

  # In-memory cache (5-minute TTL) for read performance. Invalidated on write.
  @@cache = {}
  @@cache_loaded_at = nil
  CACHE_TTL = 5.minutes

  class << self
    def get(key, default = nil)
      load_cache if cache_expired?

      setting = @@cache[key.to_s]
      return default if setting.nil?

      value = setting.typed_value
      value.nil? ? default : value
    end

    def set(key, value, value_type: "string", description: nil, category: "general", encrypted: nil, required: nil)
      setting = find_or_initialize_by(key: key)
      setting.value = value.to_s
      setting.value_type = value_type
      setting.description = description if description.present?
      setting.category = category if category.present?
      setting.encrypted = encrypted unless encrypted.nil?
      setting.required = required unless required.nil?
      setting.save!
      invalidate_cache
      setting
    end

    # Bulk upsert from the tabbed settings form. Updates existing rows and
    # creates new ones (guessing a category); blank new values are skipped.
    def batch_update(settings_hash)
      return true if settings_hash.blank?

      settings_hash = settings_hash.to_unsafe_h if settings_hash.respond_to?(:to_unsafe_h)

      transaction do
        settings_hash.each do |key, value|
          key_str = key.to_s
          value_str = value.to_s
          setting = find_by(key: key_str)

          if setting
            # Never wipe a saved secret when the field comes back blank — the
            # encrypted input submits blank to mean "keep the current value".
            next if setting.encrypted? && value_str.blank?

            setting.update!(value: value_str)
          else
            next if value_str.blank?

            is_encrypted = key_str.include?("password") || key_str.include?("secret") || key_str.include?("token") || key_str.include?("api_key")
            create!(
              key: key_str,
              value: value_str,
              category: determine_category(key_str),
              description: "Auto-created setting",
              encrypted: is_encrypted,
              value_type: "string",
              required: false,
              test_status: "untested"
            )
          end
        end
      end

      invalidate_cache
      true
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "SystemSetting batch_update failed: #{e.message}"
      false
    rescue StandardError => e
      Rails.logger.error "SystemSetting batch_update error: #{e.message}"
      false
    end

    def determine_category(key)
      case key
      when /^aws_/ then "aws"
      when /^cloudfront_/, /^cdn_/ then "cdn"
      when /^vcsi_/ then "vcsi"
      when /^smtp_/, /^email_/, /^mailer_/ then "email"
      when /_host\z/, /^app_protocol/, /_domain\z/, /_url\z/ then "urls"
      when /^company_/, /^support_/ then "company"
      when /^feature_/ then "features"
      when /^geocoder_/, /^maps_/ then "maps"
      when /^app_/, /^logo_/, /^brand/ then "branding"
      else "general"
      end
    end

    def grouped_by_category
      all.order(:key).group_by(&:category)
    end

    def invalidate_cache
      @@cache = {}
      @@cache_loaded_at = nil
    end

    def reload_cache
      invalidate_cache
      load_cache
    end

    private

    def cache_expired?
      @@cache_loaded_at.nil? || @@cache_loaded_at < CACHE_TTL.ago
    end

    def load_cache
      @@cache = all.index_by(&:key)
      @@cache_loaded_at = Time.current
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      # Table may not exist yet (migrations / boot before setup).
      @@cache = {}
      @@cache_loaded_at = Time.current
    end
  end

  def typed_value
    return nil if value.blank?

    case value_type
    when "integer" then value.to_i
    when "decimal" then value.to_d
    when "boolean" then %w[true 1 yes].include?(value.to_s.downcase)
    when "json"    then JSON.parse(value)
    else value
    end
  rescue JSON::ParserError
    nil
  end

  # Dropdown choices (value => label) for enum-like keys, else nil (free text).
  def select_options
    SELECT_OPTIONS[key]
  end

  # Mask sensitive values for display in the admin UI.
  def masked_value
    return value unless encrypted?
    return nil if value.blank?

    if value.length <= 8
      "*" * value.length
    else
      value[0..3] + ("*" * (value.length - 8)) + value[-4..]
    end
  end
end
