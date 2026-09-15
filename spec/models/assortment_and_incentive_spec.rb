require "rails_helper"

# Covers the enum->lookup-table type change, the effective-date window, and the
# it_barcode-keyed focus-SKU incentive (one barcode spans many item_keys).
RSpec.describe "Assortment types, dates & barcode incentives" do
  let(:branch) { create(:branch) }
  let(:channel) { create(:channel) }
  let(:seller) { create(:seller, branch: branch) }
  let(:store) do
    create(:store, branch: branch, channel: channel, seller: seller, vcsi_customer_ref: "C1")
  end
  let(:month) { Date.current.beginning_of_month }

  describe "Assortment.active_on (effective window)" do
    it "excludes assortments outside their effective window" do
      t = create(:assortment_type)
      p = create(:product)
      live = Assortment.create!(name: "Live", status: :active, assortment_type: t,
                                effective_from: Date.current - 5, effective_to: Date.current + 5)
      past = Assortment.create!(name: "Past", status: :active, assortment_type: t,
                                effective_from: Date.current - 30, effective_to: Date.current - 10)
      AssortmentItem.create!(assortment: live, product: p, must_stock: true)
      AssortmentItem.create!(assortment: past, product: create(:product), must_stock: true)

      ids = Assortment.resolved_items_for(store).where(must_stock: true).pluck(:product_id)
      expect(ids).to eq([p.id]) # only the in-window assortment contributes
    end
  end

  describe "Store#assortment_compliance(type_code:)" do
    it "scopes must-carry to a single assortment type" do
      focus = create(:assortment_type, code: "focus", name: "Focus")
      dist  = create(:assortment_type, code: "distribution", name: "Distribution")
      pf = create(:product)
      pd = create(:product)
      Assortment.create!(name: "F", status: :active, assortment_type: focus)
                .assortment_items.create!(product: pf, must_stock: true)
      Assortment.create!(name: "D", status: :active, assortment_type: dist)
                .assortment_items.create!(product: pd, must_stock: true)

      expect(store.assortment_compliance[:must]).to eq(2)                      # all types merged
      expect(store.assortment_compliance(type_code: "focus")[:must]).to eq(1) # focus only
      expect(store.assortment_compliance(type_code: "focus")[:gap_product_ids]).to eq([pf.id])
    end
  end

  describe "IncentiveCalculator focus_sku by it_barcode" do
    it "counts pieces for any product sharing the barcode, confirmed + projected" do
      # Two item_keys share one barcode — the classic 1 barcode : N SKUs case.
      p1 = create(:product, it_barcode: "BC1", pcs_per_case: 10)
      create(:product, it_barcode: "BC1", pcs_per_case: 10) # a sibling SKU on the same barcode
      SkuSelloutSnapshot.create!(seller: seller, it_barcode: "BC1", period_date: month, pieces: 100)

      scheme = IncentiveScheme.create!(name: "Push BC1", scheme_type: :focus_sku, status: :active,
                                       config: { "it_barcodes" => ["BC1"], "rate_per_piece" => 0.5 })

      # Presell: 2 cases of the sibling SKU (same barcode) -> 20 projected pieces.
      order = create(:order, store: store, seller: seller, branch: branch, ordered_at: month + 1.day)
      order.order_lines.create!(product: p1, quantity: 2, uom: "case_uom", line_total: 100)

      result = IncentiveCalculator.new(seller, month: month).call
      row = result[:schemes].find { |r| r[:scheme_id] == scheme.id }
      expect(row[:detail][:confirmed_pieces]).to eq(100)   # from the barcode snapshot
      expect(row[:confirmed]).to eq(50.0)                  # 100 * 0.50
      expect(row[:detail][:projected_pieces]).to eq(20)    # 2 cases * 10 pcs
    end

    it "still works with a legacy product_ids config (resolved to barcodes)" do
      p = create(:product, it_barcode: "BC9", pcs_per_case: 6)
      SkuSelloutSnapshot.create!(seller: seller, it_barcode: "BC9", period_date: month, pieces: 30)
      scheme = IncentiveScheme.create!(name: "Legacy", scheme_type: :focus_sku, status: :active,
                                       config: { "product_ids" => [p.id], "rate_per_piece" => 1 })
      row = IncentiveCalculator.new(seller, month: month).call[:schemes].find { |r| r[:scheme_id] == scheme.id }
      expect(row[:confirmed]).to eq(30.0)
    end
  end

  # Must-carry "carried" = vcsi confirmed (invoiced, net of returns) supersedes
  # presell for confirmed months; presell only provisionally fills months vcsi
  # hasn't confirmed yet.
  describe "Store#carried source: vcsi confirmed supersedes presell" do
    let(:type) { create(:assortment_type, code: "dist") }
    let(:assortment) { create(:assortment, assortment_type: type) }

    def must_stock!(barcode)
      p = create(:product, it_barcode: barcode)
      assortment.assortment_items.create!(product: p, must_stock: true)
      p
    end

    def presell!(product, at: Time.current)
      order = create(:order, store: store, seller: seller, branch: branch, ordered_at: at)
      order.order_lines.create!(product: product, quantity: 1, uom: "pc", line_total: 1)
    end

    it "fills carried from presell when vcsi has no confirmed data (provisional)" do
      b1 = must_stock!("B1"); b2 = must_stock!("B2"); must_stock!("B3")
      presell!(b1); presell!(b2)
      c = store.assortment_compliance(type_code: "dist")
      expect(c[:must]).to eq(3)
      expect(c[:carried]).to eq(2) # B1,B2 presold; B3 not
    end

    it "lets vcsi confirmed (net of returns) supersede presell for that month" do
      b1 = must_stock!("B1"); b2 = must_stock!("B2"); b3 = must_stock!("B3")
      [b1, b2, b3].each { |p| presell!(p, at: month + 2.days) } # presold all 3
      # vcsi confirms only B1,B2 invoiced; B3 returned (CN -> 0 net)
      StoreSkuSellout.create!(store: store, it_barcode: "B1", period_date: month, pieces: 12)
      StoreSkuSellout.create!(store: store, it_barcode: "B2", period_date: month, pieces: 6)
      StoreSkuSellout.create!(store: store, it_barcode: "B3", period_date: month, pieces: 0)
      c = store.assortment_compliance(type_code: "dist")
      expect(c[:carried]).to eq(2)               # vcsi truth (2 invoiced), not presell 3
      expect(c[:gap_product_ids]).to eq([b3.id]) # B3 is the gap (returned)
    end

    it "still counts new presell for a month vcsi hasn't confirmed yet (cross-month)" do
      b1 = must_stock!("B1"); b2 = must_stock!("B2")
      last_month = month - 1.month
      StoreSkuSellout.create!(store: store, it_barcode: "B1", period_date: last_month, pieces: 10)
      presell!(b2, at: Time.current) # this month, unconfirmed -> provisional
      c = store.assortment_compliance(type_code: "dist")
      expect(c[:carried]).to eq(2) # B1 confirmed (last month) + B2 presell (this month)
    end
  end
end
