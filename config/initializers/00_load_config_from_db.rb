# frozen_string_literal: true

# Runs early (00_ prefix) to hydrate credentials from the system_settings
# table into ENV BEFORE Active Storage parses config/storage.yml. This lets S3
# and CloudFront config live in the database (editable from the admin UI)
# while storage.yml keeps ENV fallbacks so boot never fails.
#
# Uses raw SQL (not the SystemSetting model) so it is safe even before the
# model/cache is loaded, and is fully guarded against a missing DB/table.
begin
  if ActiveRecord::Base.connection.table_exists?("system_settings")
    fetch = ->(key) do
      ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(
          ["SELECT value FROM system_settings WHERE key = ? LIMIT 1", key]
        )
      )
    end

    {
      "aws_access_key_id"     => "AWS_ACCESS_KEY_ID",
      "aws_secret_access_key" => "AWS_SECRET_ACCESS_KEY",
      "aws_region"            => "AWS_REGION",
      "aws_bucket"            => "AWS_BUCKET",
      "cloudfront_host"       => "CLOUDFRONT_HOST",
      "vcsi_rise_base_url"    => "VCSI_RISE_BASE_URL",
      "vcsi_rise_api_token"   => "VCSI_RISE_API_TOKEN"
    }.each do |setting_key, env_key|
      value = fetch.call(setting_key)
      ENV[env_key] = value if value.present?
    end

    Rails.logger.info "Config loaded from SystemSettings (bucket=#{ENV['AWS_BUCKET']})" if ENV["AWS_BUCKET"].present?
  end
rescue StandardError => e
  # DB may not be ready (asset precompile, initial migrations, etc.).
  Rails.logger.debug { "Could not load config from database: #{e.message}" }
end
