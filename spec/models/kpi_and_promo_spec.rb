require "rails_helper"

RSpec.describe "KPIs, compliance, and promo limits" do
  let(:branch) { create(:branch) }
  let(:seller) { create(:seller, branch: branch) }
  let(:store)  { create(:store, branch: branch, seller: seller) }
  let(:month)  { Date.current.beginning_of_month }

  describe "Store#active_in_vcsi? (invoiced this period)" do
    it "is active only when it has store-grain sellout > 0 this month" do
      expect(store.active_in_vcsi?(month)).to be(false)
      SelloutSnapshot.create!(store: store, seller_id: nil, product_id: nil, branch: branch,
                              period_type: :mtd, period_date: month, amount: 5_000)
      expect(store.active_in_vcsi?(month)).to be(true)
      expect(Store.active_in_vcsi(month)).to include(store)
    end
  end

  describe "Seller#productive_call_pct" do
    it "counts productive (closed_with_order) over completed calls" do
      create(:store, branch: branch).tap do |s2|
        Visit.create!(seller: seller, store: store, client_uuid: SecureRandom.uuid,
                      visit_date: Date.current, status: :closed_with_order)
        Visit.create!(seller: seller, store: s2, client_uuid: SecureRandom.uuid,
                      visit_date: Date.current, status: :closed_no_order, no_order_reason: "store closed")
      end
      # planned/in-progress visits don't count as completed calls
      Visit.create!(seller: seller, store: store, client_uuid: SecureRandom.uuid,
                    visit_date: Date.current, status: :planned)
      expect(seller.productive_call_pct(month..Date.current)).to eq(50)
    end

    it "blends in SFA order activity — a call with an order that day is productive" do
      s2 = create(:store, branch: branch)
      Visit.create!(seller: seller, store: store, client_uuid: SecureRandom.uuid,
                    visit_date: Date.current, status: :closed_with_order)
      # A no-order visit, but an order WAS placed there today -> now productive.
      Visit.create!(seller: seller, store: s2, client_uuid: SecureRandom.uuid,
                    visit_date: Date.current, status: :closed_no_order, no_order_reason: "n/a")
      create(:order, seller: seller, store: s2, branch: branch, ordered_at: Time.current)
      expect(seller.productive_call_pct(month..Date.current)).to eq(100)
    end

    it "is nil with no completed calls" do
      expect(seller.productive_call_pct(month..Date.current)).to be_nil
    end
  end

  describe "Store#assortment_compliance" do
    it "measures ordered must-stock SKUs against the resolved must-carry list" do
      p1 = create(:product)
      p2 = create(:product)
      assortment = Assortment.create!(name: "MS", status: :active, assortment_type: create(:assortment_type))
      AssortmentItem.create!(assortment: assortment, product: p1, must_stock: true)
      AssortmentItem.create!(assortment: assortment, product: p2, must_stock: true)

      # order only p1 -> 1 of 2 carried
      order = create(:order, store: store, seller: seller, branch: branch, ordered_at: 2.days.ago)
      order.order_lines.create!(product: p1, quantity: 1, uom: "case_uom", line_total: 10)

      c = store.assortment_compliance
      expect(c[:must]).to eq(2)
      expect(c[:carried]).to eq(1)
      expect(c[:pct]).to eq(50)
      expect(c[:gap_product_ids]).to eq([p2.id])
    end

    it "is nil when no must-stock is defined for the store" do
      expect(store.assortment_compliance).to be_nil
    end
  end

  describe "Promo per-store availment limit" do
    let(:promo) do
      Promo.create!(code: "PZ#{SecureRandom.hex(2)}", name: "One per store", status: :active,
                    start_date: Date.current - 3, end_date: Date.current + 3, per_store_limit: 1)
    end

    it "allows up to the limit within the window, then blocks" do
      expect(promo.available_for?(store)).to be(true)
      order = create(:order, store: store, seller: seller, branch: branch, ordered_at: Time.current)
      order.order_lines.create!(product: create(:product), promo_id: promo.id, quantity: 1, uom: "case_uom", line_total: 10)
      expect(promo.avails_for(store)).to eq(1)
      expect(promo.available_for?(store)).to be(false)
    end

    it "treats blank/0 limit as unlimited" do
      promo.update!(per_store_limit: nil)
      order = create(:order, store: store, seller: seller, branch: branch, ordered_at: Time.current)
      order.order_lines.create!(product: create(:product), promo_id: promo.id, quantity: 1, uom: "case_uom", line_total: 10)
      expect(promo.available_for?(store)).to be(true)
    end

    it "ignores avails outside the promo window" do
      order = create(:order, store: store, seller: seller, branch: branch, ordered_at: 30.days.ago)
      order.order_lines.create!(product: create(:product), promo_id: promo.id, quantity: 1, uom: "case_uom", line_total: 10)
      expect(promo.avails_for(store)).to eq(0)
      expect(promo.available_for?(store)).to be(true)
    end
  end
end
