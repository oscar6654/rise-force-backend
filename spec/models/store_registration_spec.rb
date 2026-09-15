require "rails_helper"

RSpec.describe StoreRegistration do
  let(:reviewer) { create(:user) }

  describe "#provision_store! default category" do
    it "assigns the configurable enrollment default when no category is proposed" do
      allow(SystemSetting).to receive(:get).and_call_original
      allow(SystemSetting).to receive(:get).with("default_enrollment_category", "silver").and_return("bronze")
      allow(SystemSetting).to receive(:get).with("provisional_code_prefix", "PROV").and_return("PROV")

      reg = create(:store_registration, proposed_category: nil)
      store = reg.provision_store!

      expect(store).to be_provisional
      expect(store.category).to eq("bronze")
      expect(store.provisional_code).to be_present
    end

    it "prefers an explicitly proposed category over the default" do
      reg = create(:store_registration, proposed_category: :gold)
      expect(reg.provision_store!.category).to eq("gold")
    end

    it "is idempotent" do
      reg = create(:store_registration)
      first = reg.provision_store!
      expect(reg.provision_store!).to eq(first)
    end
  end

  describe "#approve! channel/category reassignment" do
    it "lets the reviewer reassign channel and category at approval" do
      channel = create(:channel)
      reg = create(:store_registration, proposed_category: nil)
      reg.provision_store!

      store = reg.approve!(reviewer: reviewer, permanent_code: "ST-APPROVED",
                           channel_id: channel.id, category_code: "platinum")

      expect(store).to be_active
      expect(store.store_code).to eq("ST-APPROVED")
      expect(store.channel_id).to eq(channel.id)
      expect(store.category).to eq("platinum")
      expect(reg.reload).to be_approved
    end

    it "keeps the provisioned default category when the reviewer leaves it blank" do
      reg = create(:store_registration, proposed_category: :silver)
      reg.provision_store!

      store = reg.approve!(reviewer: reviewer, permanent_code: "ST-KEEP",
                           channel_id: nil, category_code: nil)

      expect(store.category).to eq("silver")
    end

    it "slots the store onto the route with a visit day so it lands on the call list" do
      seller = create(:seller)
      route = Route.create!(seller: seller, branch: seller.branch, code: "R1", name: "Route 1")
      reg = create(:store_registration, seller: seller, branch: seller.branch)
      reg.provision_store!

      store = reg.approve!(reviewer: reviewer, permanent_code: "ST-ROUTE",
                           route_id: route.id, visit_day: "wed", visit_frequency: "f4")

      expect(store.route_id).to eq(route.id)
      expect(store.visit_day).to eq("wed")
      expect(store).to be_freq_f4
      expect(store.visit_sequence).to eq(1)
      # Due on a Wednesday, per the assigned frequency/day.
      expect(store.due_on?(Date.new(2026, 9, 16))).to be(true) # a Wednesday
    end

    it "defaults the visit day to the weekday the seller enrolled it" do
      reg = create(:store_registration)
      reg.update_column(:created_at, Time.zone.local(2026, 9, 15, 10)) # a Tuesday
      reg.provision_store!

      store = reg.approve!(reviewer: reviewer, permanent_code: "ST-DAY")
      expect(store.visit_day).to eq("tue")
    end
  end
end
