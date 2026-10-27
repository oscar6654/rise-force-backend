require "rails_helper"

RSpec.describe "Order batches console", type: :request do
  include Warden::Test::Helpers
  let(:user) { create(:user, branch_id: nil) }

  before do
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
    allow_any_instance_of(User).to receive(:all_branches?).and_return(true)
    login_as(user, scope: :user)
  end

  # A login-group / OSB rep's order carries the STORE's branch, which can differ
  # from the seller's own master branch. The build must use the order's branch.
  it "builds a batch when the order's branch differs from the seller's master branch" do
    seller_branch = create(:branch, code: "B2")
    order_branch  = create(:branch, code: "B5")
    seller = create(:seller, branch: seller_branch) # master branch B2
    store  = create(:store, branch: order_branch)
    order  = create(:order, seller: seller, store: store, branch: order_branch,
                    status: :submitted, total_amount: 50)

    post build_order_batches_path, params: { seller_id: seller.id, branch_id: order_branch.id }

    expect(response).to have_http_status(:redirect)
    expect(order.reload.order_batch_id).to be_present
    batch = OrderBatch.find(order.order_batch_id)
    expect(batch.branch).to eq(order_branch)
    expect(batch.seller).to eq(seller)
  end

  it "includes delivery_date + remarks columns in the download CSV" do
    branch = create(:branch)
    seller = create(:seller, branch: branch)
    store  = create(:store, branch: branch)
    prod   = create(:product, it_barcode: "111", cs_barcode: "222")
    order  = create(:order, seller: seller, store: store, branch: branch, status: :submitted,
                    total_amount: 50, delivery_date: Date.new(2026, 10, 25), notes: "Deliver AM only")
    order.order_lines.create!(product: prod, quantity: 2, uom: :case_uom, unit_price: 25, line_total: 50)
    batch = OrderBatch.build_for(branch: branch, seller: seller, user: nil)

    get download_order_batch_path(batch)
    expect(response).to have_http_status(:ok)
    rows = CSV.parse(response.body, headers: true)
    expect(rows.headers).to include("delivery_date", "remarks")
    expect(rows.first["remarks"]).to eq("Deliver AM only")
    expect(rows.first["delivery_date"]).to eq("2026-10-25")
  end

  it "hides a WMS-routed seller's undispatched order from the Ready-to-batch list" do
    branch = create(:branch)
    wh = create(:warehouse, branch: branch, wms_enabled: true)
    seller = create(:seller, branch: branch, warehouse: wh, wms_enabled: true, name: "Warehouse Seller")
    store = create(:store, branch: branch)
    order = create(:order, seller: seller, store: store, branch: branch, status: :submitted, total_amount: 255)
    create(:fulfillment_order, warehouse: wh, order: order, status: :assigned)

    expect(Order.batchable_pending).not_to include(order)
    expect(Order.unbatched.wms_held).to include(order)

    get order_batches_path
    expect(response.body).not_to include("Warehouse Seller")
    expect(response.body).to include("WMS")

    # Once dispatched, it becomes batchable and shows up again.
    FulfillmentOrder.where(order: order).update_all(status: FulfillmentOrder.statuses[:dispatched])
    expect(Order.batchable_pending).to include(order)
  end

  it "holds a split WMS order until EVERY fulfillment order is dispatched" do
    branch = create(:branch)
    wh = create(:warehouse, branch: branch, wms_enabled: true)
    seller = create(:seller, branch: branch, warehouse: wh, wms_enabled: true)
    store = create(:store, branch: branch)
    order = create(:order, seller: seller, store: store, branch: branch, status: :submitted, total_amount: 100)
    child_a = create(:fulfillment_order, warehouse: wh, order: order, status: :dispatched)
    child_b = create(:fulfillment_order, warehouse: wh, order: order, status: :checked) # sibling not dispatched yet

    # One child dispatched, one not → still held, not batchable.
    expect(Order.batchable_pending).not_to include(order)
    expect(OrderBatch.build_for(branch: branch, seller: seller, user: user)).to be_nil

    child_b.update!(status: :dispatched)
    expect(Order.batchable_pending).to include(order)
    expect(OrderBatch.build_for(branch: branch, seller: seller, user: user)).to be_present
    _ = child_a
  end

  it "does NOT batch a WMS-routed seller's order until its fulfillment order is dispatched" do
    branch = create(:branch)
    wh = create(:warehouse, branch: branch, wms_enabled: true)
    seller = create(:seller, branch: branch, warehouse: wh, wms_enabled: true)
    store = create(:store, branch: branch)
    order = create(:order, seller: seller, store: store, branch: branch, status: :submitted, total_amount: 50)

    # No dispatched fulfillment order yet → nothing to batch.
    expect(OrderBatch.build_for(branch: branch, seller: seller, user: user)).to be_nil

    # Once the fulfillment order is dispatched, the order becomes batchable.
    create(:fulfillment_order, warehouse: wh, order: order, status: :dispatched)
    batch = OrderBatch.build_for(branch: branch, seller: seller, user: user)
    expect(batch).to be_present
    expect(order.reload.order_batch_id).to eq(batch.id)
  end

  it "emits shipped_qty (not ordered qty) in the CSV when present" do
    branch = create(:branch)
    seller = create(:seller, branch: branch)
    store  = create(:store, branch: branch)
    prod   = create(:product, it_barcode: "111", cs_barcode: "222")
    order  = create(:order, seller: seller, store: store, branch: branch, status: :submitted, total_amount: 50)
    order.order_lines.create!(product: prod, quantity: 10, uom: :case_uom, unit_price: 25, line_total: 250, shipped_qty: 7)
    batch = OrderBatch.build_for(branch: branch, seller: seller, user: nil)

    get download_order_batch_path(batch)
    rows = CSV.parse(response.body, headers: true)
    expect(rows.first["qty_cases"].to_i).to eq(7) # shipped, not the ordered 10
  end

  it "still batches a same-branch order when branch_id is omitted" do
    branch = create(:branch)
    seller = create(:seller, branch: branch)
    store  = create(:store, branch: branch)
    create(:order, seller: seller, store: store, branch: branch, status: :submitted, total_amount: 50)

    post build_order_batches_path, params: { seller_id: seller.id }

    expect(response).to have_http_status(:redirect)
    expect(OrderBatch.where(seller: seller, branch: branch).count).to eq(1)
  end
end
