# frozen_string_literal: true

# Mailgun delivery method (mirrors vcsi_rise). Credentials come from
# SystemSetting (category `email`) so they're editable from the admin UI:
#   mailgun_api_key, mailgun_domain
# ActionMailer is switched to :mailgun by config/initializers/system_settings.rb
# when those settings are present.
require "mailgun-ruby"

class MailgunDeliveryMethod
  attr_accessor :settings

  def initialize(settings)
    @settings = settings
  end

  def deliver!(mail)
    client = Mailgun::Client.new(api_key)
    message = {
      from: mail.from&.first,
      to: mail.to&.join(","),
      subject: mail.subject,
      text: mail.text_part&.body&.decoded,
      html: mail.html_part&.body&.decoded
    }

    if message[:html].nil? && message[:text].nil?
      if mail.content_type&.include?("text/html")
        message[:html] = mail.body.decoded
      else
        message[:text] = mail.body.decoded
      end
    end

    client.send_message(domain, message.compact)
  end

  private

  def api_key
    SystemSetting.get("mailgun_api_key", @settings[:api_key])
  rescue StandardError
    @settings[:api_key]
  end

  def domain
    SystemSetting.get("mailgun_domain", @settings[:domain])
  rescue StandardError
    @settings[:domain]
  end
end

ActionMailer::Base.add_delivery_method :mailgun, MailgunDeliveryMethod,
  api_key: ENV["MAILGUN_API_KEY"], domain: ENV["MAILGUN_DOMAIN"]
