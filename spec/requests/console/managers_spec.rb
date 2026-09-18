require "rails_helper"

RSpec.describe "Managers console", type: :request do
  include Warden::Test::Helpers

  let(:branch) { create(:branch) }
  let(:user)   { create(:user, branch_id: nil) }
  let(:s1) { create(:seller, branch: branch, name: "Aling A") }
  let(:s2) { create(:seller, branch: branch, name: "Aling B") }

  before do
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
    login_as(user, scope: :user)
  end

  it "renders the new-manager form with the seller multi-select" do
    s1; s2
    get new_manager_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sellers under this manager")
    expect(response.body).to include("Aling A")
  end

  it "creates a manager and tags the selected sellers" do
    post managers_path, params: { manager: { code: "MGR-N", name: "Nora", pin: "1111", seller_ids: ["", s1.id.to_s, s2.id.to_s] } }
    expect(response).to redirect_to(managers_path)
    m = Manager.find_by(code: "MGR-N")
    expect(m.sellers).to contain_exactly(s1, s2)
  end

  it "updates the tagged sellers, and clears via the blank hidden field" do
    m = Manager.create!(code: "MGR-U", name: "Up")
    m.sellers << [s1, s2]
    patch manager_path(m), params: { manager: { seller_ids: ["", s1.id.to_s] } }
    expect(m.reload.sellers).to contain_exactly(s1)
  end
end
