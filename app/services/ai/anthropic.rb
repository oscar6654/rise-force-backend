# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module Ai
  # Thin Anthropic Messages API client (same Net::HTTP pattern as VcsiRise::Client).
  # Credentials + model come from SystemSetting (category `ai`), set in the admin
  # console — never hard-coded. Fails SOFT: any error returns nil so AI is always
  # an optional enhancement, never a hard dependency of a screen.
  class Anthropic
    ENDPOINT = "https://api.anthropic.com/v1/messages"
    VERSION  = "2023-06-01"

    def self.enabled?
      SystemSetting.get("ai_features_enabled", "false").to_s == "true" &&
        SystemSetting.get("anthropic_api_key").present?
    end

    attr_reader :model

    def initialize(api_key: nil, model: nil)
      @api_key = api_key || SystemSetting.get("anthropic_api_key")
      @model = model || SystemSetting.get("ai_model", "claude-haiku-5-5")
    end

    def available?
      @api_key.present?
    end

    # Returns the completion text, or nil on any failure.
    def complete(system:, prompt:, max_tokens: 400)
      return nil unless available?

      uri = URI(ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 40

      req = Net::HTTP::Post.new(uri)
      req["x-api-key"] = @api_key
      req["anthropic-version"] = VERSION
      req["content-type"] = "application/json"
      req.body = {
        model: @model, max_tokens: max_tokens, system: system,
        messages: [{ role: "user", content: prompt }],
      }.to_json

      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[Ai::Anthropic] HTTP #{res.code}: #{res.body.to_s[0, 300]}")
        return nil
      end
      # The response `content` is a list of blocks; on thinking-enabled models
      # (Haiku 5.5 thinks by default) block 0 is a `thinking` block, so pick the
      # first `text` block rather than assuming index 0.
      json = JSON.parse(res.body)
      Array(json["content"]).find { |b| b["type"] == "text" }&.dig("text")&.strip
    rescue StandardError => e
      Rails.logger.warn("[Ai::Anthropic] #{e.class}: #{e.message}")
      nil
    end
  end
end
