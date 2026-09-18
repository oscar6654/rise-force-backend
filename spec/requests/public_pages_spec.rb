require "rails_helper"

RSpec.describe "Public legal/support pages", type: :request do
  it "serves the privacy policy with no login" do
    get "/privacy"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Privacy Policy")
    expect(response.body).to include("No push notifications")
    expect(response.body).to include("VALUESALES, INC.")
    expect(response.body).to include("info@valuesalesinc.com")
  end

  it "serves terms, support, data-deletion, and the legal index" do
    %w[/terms /support /data-deletion /legal].each do |path|
      get path
      expect(response).to have_http_status(:ok), "#{path} returned #{response.status}"
    end
  end

  it "redirects /account-deletion to /data-deletion" do
    get "/account-deletion"
    expect(response).to redirect_to("/data-deletion")
  end
end
