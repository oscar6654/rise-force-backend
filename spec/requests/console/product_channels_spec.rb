require "rails_helper"

RSpec.describe "Channel availability console", type: :request do
  include Warden::Test::Helpers

  let(:user) { create(:user, branch_id: nil) }
  let!(:product) { create(:product, sku: "SKU-COFFEE", description: "Coffee") }
  let!(:grocery) { create(:channel, code: "GROC", name: "Grocery") }

  before do
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
    login_as(user, scope: :user)
  end

  it "renders the mapping index with the universal/restricted summary" do
    ProductChannel.create!(product: product, channel: grocery)
    get product_channels_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Channel availability")
    expect(response.body).to include("Grocery")
    expect(response.body).to include("SKU-COFFEE")
  end

  it "imports a mapping CSV through the shared importer flow" do
    csv = "item_key,channel_code\nSKU-COFFEE,GROC\n"
    file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "map.csv")
    post imports_path("product_channels"), params: { file: file }
    expect(response).to have_http_status(:redirect)
    expect(ProductChannel.where(product: product, channel: grocery)).to exist
  end
end
