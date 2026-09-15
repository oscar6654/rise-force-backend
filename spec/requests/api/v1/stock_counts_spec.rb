require "rails_helper"

RSpec.describe "Api::V1::StockCounts", type: :request do
  let(:branch)  { create(:branch) }
  let(:seller)  { create(:seller, branch: branch) }
  let(:store)   { create(:store, branch: branch) }
  let(:product) { create(:product) }
  let(:visit) do
    Visit.create!(client_uuid: "visit-1", seller: seller, store: store,
                  started_at: Time.current, status: :in_progress)
  end

  def auth_header
    jti = SecureRandom.uuid
    DeviceToken.create!(seller: seller, jti: jti, device_id: "d1")
    { "Authorization" => "Bearer #{JsonWebToken.encode({ seller_id: seller.id, jti: jti })}" }
  end

  def post_count(qty, uuid)
    post "/api/v1/stock_counts",
         params: { visit_client_uuid: visit.client_uuid,
                   counts: [{ client_uuid: uuid, product_id: product.id, qty: qty }] },
         headers: auth_header, as: :json
  end

  it "re-counting the same product on a visit UPDATES it instead of 404-ing" do
    post_count(2, "c-1")
    expect(response).to have_http_status(:created)

    # Second save (new client_uuid, as the app generates) must not conflict on
    # the unique (visit_id, product_id) index.
    post_count(5, "c-2")
    expect(response).to have_http_status(:created)

    counts = StockCount.where(visit: visit, product_id: product.id)
    expect(counts.count).to eq(1)
    expect(counts.first.qty).to eq(5)
  end

  it "reads back the current visit's counts via last_stock_counts" do
    post_count(3, "c-9")
    get "/api/v1/stores/#{store.id}/last_stock_counts",
        params: { visit_client_uuid: visit.client_uuid }, headers: auth_header
    body = JSON.parse(response.body)
    expect(body["data"]).to eq([{ "product_id" => product.id, "qty" => "3.0" }])
  end
end
