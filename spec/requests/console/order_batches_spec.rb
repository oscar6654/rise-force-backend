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
