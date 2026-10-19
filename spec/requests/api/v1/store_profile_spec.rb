require "rails_helper"

RSpec.describe "Api::V1 store profile", type: :request do
  let(:branch) { create(:branch) }
  let(:seller) { create(:seller, branch: branch) }
  let!(:store) { create(:store, branch: branch, seller: seller) }

  def auth_header
    jti = SecureRandom.uuid
    DeviceToken.create!(seller: seller, jti: jti, device_id: "d1")
    { "Authorization" => "Bearer #{JsonWebToken.encode({ seller_id: seller.id, jti: jti })}" }
  end

  it "maps must-stock SKUs to the catalog's barcode representative in assortment_type_skus" do
    type = create(:assortment_type, code: "dist", name: "Distribution")
    rep     = create(:product, it_barcode: "BC1", case_cost: 200) # representative (highest case_cost)
    sibling = create(:product, it_barcode: "BC1", case_cost: 100) # same barcode, a smaller pack
    a = create(:assortment, assortment_type: type)
    a.assortment_items.create!(product: sibling, must_stock: true) # the must-stock item is the SIBLING

    get "/api/v1/stores/#{store.id}/profile", headers: auth_header
    expect(response).to have_http_status(:ok)
    skus = JSON.parse(response.body).dig("data", "assortment_type_skus", "dist")
    # The sibling resolves to the representative the app's catalog actually carries.
    expect(skus).to eq([rep.id])
    expect(skus).not_to include(sibling.id)
  end
end
