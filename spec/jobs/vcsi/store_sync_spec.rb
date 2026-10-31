require "rails_helper"

RSpec.describe "vcsi_rise store sync + reconciling actual" do
  include ActiveSupport::Testing::TimeHelpers
  let(:branch) { create(:branch) }
  let(:seller) { create(:seller, branch: branch) }
  let(:store)  { create(:store, branch: branch, seller: seller, vcsi_customer_ref: "CUST-1") }
  let(:month)  { Date.current.beginning_of_month }

  def stub_client(history: [], sellout: [])
    client = instance_double(VcsiRise::Client)
    allow(VcsiRise::Client).to receive(:new).and_return(client)
    allow(client).to receive(:store_history).and_return(history)
    allow(client).to receive(:store_sellout).and_return(sellout)
    client
  end

  describe Vcsi::StoreTargetComputeJob do
    it "derives target = trailing 3-mo average * (1 + growth)" do
      SystemSetting.set("store_target_months", "3")
      SystemSetting.set("store_target_growth_rate", "0.05")
      stub_client(history: [
        { "customer_id" => "CUST-1", "month" => "2026-06", "sellout" => "90000.0" },
        { "customer_id" => "CUST-1", "month" => "2026-07", "sellout" => "100000.0" },
        { "customer_id" => "CUST-1", "month" => "2026-08", "sellout" => "110000.0" }
      ])
      store # create

      described_class.perform_now

      target = StoreTarget.for_month(month).find_by(store: store)
      expect(target.basis_amount).to eq(100_000)
      expect(target.target_amount).to eq(105_000) # 100k * 1.05
      expect(target.months_used).to eq(3)
      expect(store.target_for(month)).to eq(105_000)
    end

    it "skips stores with no vcsi_rise history" do
      stub_client(history: [])
      store
      expect { described_class.perform_now }.not_to change(StoreTarget, :count)
    end
  end

  describe "to invoice (cleared by OSB download + a later sellout sync, never netted)" do
    let(:sellout_row) { [{ "customer_id" => "CUST-1", "sellout" => "3000.0", "transactions" => 1 }] }

    def place(amount, status: :submitted)
      create(:order, store: store, seller: seller, branch: branch,
                     ordered_at: 1.day.ago, total_amount: amount, status: status)
    end

    it "is NOT netted against vcsi confirmed sellout" do
      place(25_000)
      stub_client(sellout: [{ "customer_id" => "CUST-1", "sellout" => "30000.0", "transactions" => 3 }])
      Vcsi::StoreSelloutSyncJob.perform_now
      expect(store.confirmed_actual(month)).to eq(30_000)
      expect(store.pending_presell(month)).to eq(25_000) # not downloaded → still to invoice
      expect(store.blended_actual(month)).to eq(55_000)
    end

    it "stays after batch download, clears after the NEXT sellout sync" do
      place(12_000)
      batch = OrderBatch.build_for(branch: branch, seller: seller, user: nil)
      expect(store.pending_presell(month)).to eq(12_000) # batched

      batch.download!(nil)
      expect(store.pending_presell(month)).to eq(12_000) # downloaded, sync not run yet
      expect(seller.pending_presell(month)).to eq(12_000)

      stub_client(sellout: sellout_row)
      travel 1.minute do
        log = Vcsi::StoreSelloutSyncJob.perform_now
        expect(log.result_summary["orders_invoiced"]).to eq(1)
      end
      expect(store.pending_presell(month)).to eq(0)
      expect(seller.pending_presell(month)).to eq(0)
      expect(batch.reload).to be_invoiced
      expect(batch.orders.pluck(:status).uniq).to eq(["invoiced"])
    end

    it "the seller-level sellout sync clears it too" do
      place(5_000)
      OrderBatch.build_for(branch: branch, seller: seller, user: nil).download!(nil)
      client = stub_client
      allow(client).to receive(:sellout).and_return([])
      travel(1.minute) { Vcsi::SelloutSyncJob.perform_now }
      expect(store.pending_presell(month)).to eq(0)
    end

    it "a sync does not clear batches not yet downloaded, or downloaded after it started" do
      place(7_000)
      OrderBatch.build_for(branch: branch, seller: seller, user: nil) # batched only
      stub_client(sellout: sellout_row)
      Vcsi::StoreSelloutSyncJob.perform_now
      expect(store.pending_presell(month)).to eq(7_000)

      batch = OrderBatch.last
      batch.download!(nil)
      expect(OrderBatch.mark_invoiced_after_sync!(1.minute.ago)).to eq(0) # sync started before download
      expect(store.pending_presell(month)).to eq(7_000)
    end

    it "excludes cancelled orders" do
      place(9_000, status: :cancelled)
      expect(store.pending_presell(month)).to eq(0)
    end
  end
end
