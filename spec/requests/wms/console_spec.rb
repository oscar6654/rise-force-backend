require "rails_helper"

# Smoke-renders the WMS console pages so ERB/route errors surface in CI.
RSpec.describe "WMS console", type: :request do
  include Warden::Test::Helpers
  let(:user) { create(:user, branch_id: nil) }

  before do
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
    allow_any_instance_of(User).to receive(:all_branches?).and_return(true)
    login_as(user, scope: :user)
  end

  it "renders the index pages" do
    wh = create(:warehouse)
    create(:storage_location, warehouse: wh)
    create(:warehouse_staff, warehouse: wh)
    create(:fulfillment_order, warehouse: wh)

    [wms_storage_locations_path, wms_inventory_index_path, wms_receipts_path, wms_staff_index_path,
     wms_demand_index_path, wms_cycle_counts_path, wms_stock_movements_path, wms_returns_path,
     new_wms_storage_location_path, new_wms_staff_path, new_wms_cycle_count_path, new_wms_return_path].each do |path|
      get path
      expect(response).to have_http_status(:ok), "#{path} returned #{response.status}"
    end
  end

  it "renders a pick job and reassigns the picker (override)" do
    wh = create(:warehouse)
    p1 = create(:warehouse_staff, warehouse: wh, roles: %w[pick], name: "Picker One")
    p2 = create(:warehouse_staff, warehouse: wh, roles: %w[pick], name: "Picker Two")
    fo = create(:fulfillment_order, warehouse: wh, status: :assigned, assigned_to: p1)

    get wms_demand_path(fo)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Reassign picker")
    expect(response.body).to include("Picker Two")

    post reassign_wms_demand_path(fo), params: { warehouse_staff_id: p2.id }
    expect(response).to have_http_status(:redirect)
    expect(fo.reload.assigned_to).to eq(p2)
  end

  it "opens + reconciles a cycle count through the console" do
    wh = create(:warehouse)
    loc = create(:storage_location, warehouse: wh)
    create(:inventory_lot, warehouse: wh, storage_location: loc, product: create(:product), qty_on_hand: 40)

    post wms_cycle_counts_path, params: { storage_location_id: loc.id }
    count = CycleCount.last
    expect(count.system_qty.to_i).to eq(40)

    Wms::CycleCountService.new(count).submit!(counted_qty: 38)
    post reconcile_wms_cycle_count_path(count)
    expect(count.reload.status).to eq("reconciled")
  end
end
