require "rails_helper"

RSpec.describe "vcsi_rise store sync + reconciling actual" do
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

  describe "reconciling actual (presell nets against confirmed, clears as vcsi syncs)" do
    it "to-invoice = SFA orders NET of confirmed sellout, so it clears as vcsi confirms" do
      create(:order, store: store, seller: seller, branch: branch,
                     ordered_at: 2.days.ago, total_amount: 25_000, status: :submitted)
      expect(store.pending_presell(month)).to eq(25_000) # nothing confirmed yet

      # A sync brings vcsi confirmed sellout — to-invoice shrinks by the confirmed.
      stub_client(sellout: [{ "customer_id" => "CUST-1", "sellout" => "20000.0", "transactions" => 2 }])
      Vcsi::StoreSelloutSyncJob.perform_now
      expect(store.confirmed_actual(month)).to eq(20_000)
      expect(store.pending_presell(month)).to eq(5_000)  # 25k ordered − 20k confirmed
      expect(store.blended_actual(month)).to eq(25_000)  # max(confirmed, presell)

      # Once confirmed catches up to / exceeds presell, to-invoice clears to 0.
      stub_client(sellout: [{ "customer_id" => "CUST-1", "sellout" => "30000.0", "transactions" => 3 }])
      Vcsi::StoreSelloutSyncJob.perform_now
      expect(store.pending_presell(month)).to eq(0)
      expect(store.blended_actual(month)).to eq(30_000)
    end

    it "is not inflated when vcsi confirmed sellout is NEGATIVE (net credit notes)" do
      # Nets only POSITIVE confirmed, so a negative net can't blow it up
      # (the old prod bug: 30 - (-14000) = 14000+).
      create(:order, store: store, seller: seller, branch: branch,
                     ordered_at: 1.day.ago, total_amount: 30, status: :submitted)
      stub_client(sellout: [{ "customer_id" => "CUST-1", "sellout" => "-14000.0", "transactions" => 1 }])
      Vcsi::StoreSelloutSyncJob.perform_now
      expect(store.confirmed_actual(month)).to eq(-14_000)
      expect(store.pending_presell(month)).to eq(30) # the order value, not 14,030
    end

    it "clears to-invoice once the order's batch is downloaded for OSB" do
      create(:order, store: store, seller: seller, branch: branch,
                     ordered_at: 1.day.ago, total_amount: 12_000, status: :submitted)
      expect(store.pending_presell(month)).to eq(12_000)
      expect(seller.pending_presell(month)).to eq(12_000)

      batch = OrderBatch.build_for(branch: branch, seller: seller, user: nil)
      expect(store.pending_presell(month)).to eq(12_000) # batched, not yet handed off

      batch.download!(nil)
      expect(store.pending_presell(month)).to eq(0)
      expect(seller.pending_presell(month)).to eq(0)
    end

    it "excludes cancelled orders from presell" do
      create(:order, store: store, seller: seller, branch: branch,
                     ordered_at: 1.day.ago, total_amount: 9_000, status: :cancelled)
      expect(store.pending_presell(month)).to eq(0)
    end
  end
end
