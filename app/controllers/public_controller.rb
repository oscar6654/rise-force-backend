# Publicly accessible pages (NO login) for App Store / Play Store review and for
# users: privacy policy, terms, support, and data/account deletion. Content is
# driven by SystemSetting so you can set company + contact details without code.
class PublicController < ActionController::Base
  layout "public"

  helper_method :cfg

  def index; end        # /legal — links to all pages
  def privacy; end
  def terms; end
  def support; end
  def data_deletion; end

  private

  def cfg
    @cfg ||= {
      company: SystemSetting.get("company_legal_name", "VALUESALES, INC."),
      app: SystemSetting.get("app_display_name", "Rise Force"),
      email: SystemSetting.get("privacy_contact_email", "info@valuesalesinc.com"),
      phone: SystemSetting.get("privacy_contact_phone", ""),
      address: SystemSetting.get("company_address", ""),
      effective: SystemSetting.get("privacy_effective_date", Date.current.strftime("%B %-d, %Y")),
    }
  end
end
