require "rails_helper"

RSpec.describe Visits::Housekeeping do
  let(:branch) { create(:branch) }
  let(:seller) { create(:seller, branch: branch) }
  let(:store)  { create(:store, branch: branch) }

  def visit(started_at:, uuid: SecureRandom.uuid)
    Visit.create!(client_uuid: uuid, seller: seller, store: store,
                  started_at: started_at, visit_date: started_at.to_date, status: :in_progress)
  end

  it "auto-closes a visit left open from a previous day" do
    v = visit(started_at: 2.days.ago)
    expect { described_class.close_stale! }.to change { v.reload.status }.from("in_progress").to("closed_no_order")
    expect(v.no_order_reason).to eq("Auto-closed — not checked out")
    expect(v.ended_at).to be_present
  end

  it "keeps one visit per store/day and closes the same-day duplicates" do
    keep = visit(started_at: Time.current.change(hour: 9))
    dup1 = visit(started_at: Time.current.change(hour: 10))
    dup2 = visit(started_at: Time.current.change(hour: 11))
    # keep has real work → it must survive even though it's the earliest.
    keep.stock_counts.create!(client_uuid: "sc-1", product: create(:product), qty: 3)

    described_class.close_stale!

    expect(keep.reload.status).to eq("in_progress")
    expect(dup1.reload.status).to eq("closed_no_order")
    expect(dup2.reload.status).to eq("closed_no_order")
  end

  it "leaves a single open visit for today alone" do
    v = visit(started_at: 1.hour.ago)
    expect { described_class.close_stale! }.not_to change { v.reload.status }
  end

  it "closes a duplicate with an order as closed_with_order" do
    keep = visit(started_at: Time.current.change(hour: 9))
    withorder = visit(started_at: Time.current.change(hour: 8))
    Order.create!(client_uuid: "o-1", seller: seller, store: store, branch: branch,
                  ordered_at: Time.current, visit: withorder)
    keep.stock_counts.create!(client_uuid: "sc-2", product: create(:product), qty: 1)

    described_class.close_stale!
    # keep has stock counts (weight) but withorder has an order (weight 1000) → withorder kept.
    expect(withorder.reload.status).to eq("in_progress")
    expect(keep.reload.status).to eq("closed_no_order")
  end
end
