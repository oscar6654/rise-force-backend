require "rails_helper"

# End-to-end picker flow over the mobile API: login as warehouse staff, list the
# assigned job, start it, confirm a pick, and reject a wrong scan / wrong role.
RSpec.describe "Api::V1::Wms picker flow", type: :request do
  let(:warehouse) { create(:warehouse) }
  let(:product)   { create(:product, pcs_per_case: 10, it_barcode: "BC1") }
  let(:rack)      { create(:storage_location, warehouse: warehouse, loc_code: "A-01") }
  let!(:staff)    { create(:warehouse_staff, warehouse: warehouse, staff_code: "PICK1", roles: %w[pick]) }

  def auth_header(ws)
    jti = SecureRandom.uuid
    DeviceToken.create!(warehouse_staff_id: ws.id, role: "staff", jti: jti, device_id: "d1")
    { "Authorization" => "Bearer #{JsonWebToken.encode({ warehouse_staff_id: ws.id, jti: jti, role: 'staff' })}" }
  end

  def allocated_fo
    create(:inventory_lot, warehouse: warehouse, product: product, storage_location: rack,
           qty_on_hand: 100, received_date: Date.today, status: :active)
    fo = create(:fulfillment_order, warehouse: warehouse, assigned_to: staff, status: :pending)
    fo.fulfillment_lines.create!(product: product, qty_demanded: 20, uom: :pc)
    Wms::AllocationService.new(fo).allocate!
    fo.update!(status: :assigned, assigned_to: staff)
    fo
  end

  it "logs in a warehouse staff and returns the role set" do
    post "/api/v1/auth/login", params: { seller_code: "PICK1", pin: "1234", device_id: "d1" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "role")).to eq("staff")
    expect(response.parsed_body.dig("data", "roles")).to eq(["pick"])
  end

  it "lists assigned jobs, starts, and confirms a pick" do
    fo = allocated_fo
    headers = auth_header(staff)

    get "/api/v1/wms/tasks", headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["data"].first["reference_no"]).to eq(fo.reference_no)

    post "/api/v1/wms/tasks/#{fo.id}/start", headers: headers
    expect(response).to have_http_status(:ok)

    alloc = fo.pick_allocations.first
    post "/api/v1/wms/picks/#{alloc.id}/confirm", headers: headers, as: :json,
         params: { qty_picked: 20, barcode: "BC1", location_code: "A-01" }
    expect(response).to have_http_status(:ok)
    expect(fo.reload.status).to eq("picked")
    expect(alloc.reload.status).to eq("picked")
  end

  it "rejects a wrong item scan" do
    fo = allocated_fo
    headers = auth_header(staff)
    post "/api/v1/wms/tasks/#{fo.id}/start", headers: headers
    alloc = fo.pick_allocations.first
    post "/api/v1/wms/picks/#{alloc.id}/confirm", headers: headers, as: :json,
         params: { qty_picked: 20, barcode: "WRONG", location_code: "A-01" }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig("error", "code")).to eq("pick_failed")
  end

  it "denies a check-only endpoint to a pick-only staff" do
    headers = auth_header(staff) # roles: [pick]
    get "/api/v1/wms/checks", headers: headers
    expect(response).to have_http_status(:unauthorized)
  end
end
