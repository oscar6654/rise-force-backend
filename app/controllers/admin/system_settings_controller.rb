module Admin
  class SystemSettingsController < ApplicationController
    before_action -> { authorize!(:system_setting, :view) }, only: [:index]
    before_action -> { authorize!(:system_setting, :update) },
                  only: [:batch_update, :test_email, :test_connection]

    # Ordered tabs shown in the settings UI.
    TABS = %w[email aws cdn vcsi mobile stores urls company branding features general].freeze

    def index
      @tabs = TABS
      @active_tab = params[:tab].presence_in(TABS) || TABS.first
      @grouped = SystemSetting.grouped_by_category
    end

    def batch_update
      if SystemSetting.batch_update(params[:settings])
        redirect_to admin_system_settings_path(tab: params[:tab]),
                    notice: "Settings saved. Email, storage (S3/CloudFront) and URL changes take effect after restart."
      else
        redirect_to admin_system_settings_path(tab: params[:tab]),
                    alert: "Could not save settings."
      end
    end

    def test_email
      to = params[:to].presence || current_user.email
      SettingsMailer.test_email(to).deliver_now
      mark_test("email", :success)
      redirect_to admin_system_settings_path(tab: "email"), notice: "Test email sent to #{to}."
    rescue StandardError => e
      mark_test("email", :failed)
      redirect_to admin_system_settings_path(tab: "email"), alert: "Test email failed: #{e.message}"
    end

    # Verifies the vcsi_rise API is reachable with the configured credentials.
    def test_connection
      result = VcsiRise::Client.new.ping
      if result[:ok]
        mark_test("vcsi", :success)
        redirect_to admin_system_settings_path(tab: "vcsi"), notice: "vcsi_rise reachable (#{result[:detail]})."
      else
        mark_test("vcsi", :failed)
        redirect_to admin_system_settings_path(tab: "vcsi"), alert: "vcsi_rise connection failed: #{result[:detail]}"
      end
    end

    private

    def mark_test(category, status)
      SystemSetting.by_category(category).update_all(test_status: status.to_s)
      SystemSetting.invalidate_cache
    end
  end
end
