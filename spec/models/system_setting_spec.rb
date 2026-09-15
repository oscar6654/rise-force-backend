require "rails_helper"

RSpec.describe SystemSetting do
  describe ".batch_update" do
    it "keeps a saved secret when the encrypted field comes back blank" do
      SystemSetting.create!(key: "vcsi_rise_api_token", value: "tok-abc123", value_type: "string",
                            category: "vcsi", encrypted: true)
      # Saving the vcsi tab resubmits a blank token (leave-blank-to-keep).
      SystemSetting.batch_update("vcsi_rise_api_token" => "", "vcsi_rise_base_url" => "https://erp.example")

      expect(SystemSetting.find_by(key: "vcsi_rise_api_token").value).to eq("tok-abc123")
      expect(SystemSetting.get("vcsi_rise_base_url")).to eq("https://erp.example")
    end

    it "still updates a secret when a new value is provided" do
      SystemSetting.create!(key: "smtp_password", value: "old", value_type: "string",
                            category: "email", encrypted: true)
      SystemSetting.batch_update("smtp_password" => "new-secret")
      expect(SystemSetting.get("smtp_password")).to eq("new-secret")
    end
  end

  describe "#select_options" do
    it "returns labelled choices for enum-like keys and nil for free text" do
      geofence = SystemSetting.new(key: "checkin_geofence_mode", value: "soft")
      expect(geofence.select_options.keys).to contain_exactly("warn", "soft", "hard")

      free = SystemSetting.new(key: "app_host", value: "localhost")
      expect(free.select_options).to be_nil
    end
  end
end
