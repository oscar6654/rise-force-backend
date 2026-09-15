class ApplicationMailer < ActionMailer::Base
  # From address is configurable via System Settings (white-label).
  default from: -> { SystemSetting.get("email_from", "no-reply@sfa.local") rescue "no-reply@sfa.local" }
  layout "mailer"
end
