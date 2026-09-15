class SettingsMailer < ApplicationMailer
  # Sent from the admin System Settings screen to verify SMTP config.
  def test_email(to_email)
    @app_name = SystemSetting.get("app_name", "SFA Console")
    @sent_at = Time.current
    mail(to: to_email, subject: "#{@app_name} — test email")
  end
end
