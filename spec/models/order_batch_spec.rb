require "rails_helper"

RSpec.describe OrderBatch do
  let(:branch) { create(:branch) }
  let(:seller) { create(:seller, branch: branch) }
  let(:store)  { create(:store, branch: branch) }

  def submitted_order
    create(:order, seller: seller, store: store, branch: branch, status: :submitted, total_amount: 50)
  end

  describe ".build_for" do
    it "scoops unbatched submitted orders into a locked batch" do
      2.times { submitted_order }
      batch = described_class.build_for(branch: branch, seller: seller, user: nil)

      expect(batch.order_count).to eq(2)
      expect(batch.total_amount).to eq(100)
      expect(batch).to be_locked
      expect(batch.orders.pluck(:status).uniq).to eq(["batched"])
    end

    it "returns nil when there is nothing to batch" do
      expect(described_class.build_for(branch: branch, seller: seller, user: nil)).to be_nil
    end
  end

  describe "#download!" do
    it "marks the batch downloaded once and blocks a second download" do
      submitted_order
      batch = described_class.build_for(branch: branch, seller: seller, user: nil)

      batch.download!(nil)
      expect(batch.reload).to be_downloaded
      expect(batch.downloaded_at).to be_present
      expect(batch.orders.pluck(:status).uniq).to eq(["downloaded"])

      expect { batch.download!(nil) }.to raise_error(OrderBatch::AlreadyDownloaded)
    end
  end

  it "enforces one open batch per (branch, seller) at the DB level" do
    # build_for creates a :locked batch, so create a raw open one first
    described_class.create!(branch: branch, seller: seller, sequence: 1, status: :open,
                            batch_number: "A")
    expect do
      described_class.create!(branch: branch, seller: seller, sequence: 2, status: :open,
                              batch_number: "B")
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
