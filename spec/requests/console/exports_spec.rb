require "rails_helper"

RSpec.describe "Exports console", type: :request do
  include Warden::Test::Helpers
  let(:user) { create(:user, branch_id: nil) }

  before do
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
    login_as(user, scope: :user)
  end

  def csv_body(kind)
    get export_path(kind)
    expect(response).to have_http_status(:ok), "#{kind} → #{response.status}"
    expect(response.content_type).to include("text/csv")
    response.body
  end

  it "exports every master kind as CSV with a header row" do
    %w[products stores product_channels promos channels product_categories
       product_tiers store_categories assortments pricing].each do |kind|
      expect(CSV.parse(csv_body(kind))).not_to be_empty, "#{kind} produced no CSV"
    end
  end

  it "rejects an unknown kind" do
    get export_path("nope")
    expect(response).not_to have_http_status(:ok)
  end

  it "round-trips the store master (export columns match the importer)" do
    branch = create(:branch, code: "HO")
    chan   = create(:channel, code: "HFS")
    create(:store, store_code: "ST-9", name: "Nena", branch: branch, channel: chan, status: :inactive)

    body = csv_body("stores")
    expect(body).to include("store_code,name")
    expect(body).to include("ST-9").and include("inactive").and include("HFS")

    Store.where(store_code: "ST-9").delete_all
    Import::StoresImporter.new(body, user: user, filename: "e.csv", default_branch: branch).call
    s = Store.find_by(store_code: "ST-9")
    expect(s).to be_inactive
    expect(s.channel).to eq(chan)
  end

  it "reconstructs a multivariant promo back into importable items + tiers" do
    create(:product, it_barcode: "111")
    create(:product, it_barcode: "222")
    promo = Promo.create!(code: "MV", name: "Mix", mechanic_type: :multivariant_percent, status: :active,
                          config: { "tiers" => [{ "min_skus" => 2, "rate" => 0.08 }] })
    promo.promo_lines.create!(role: :qualifying, it_barcode: "111", min_qty: 2)
    promo.promo_lines.create!(role: :qualifying, it_barcode: "222", min_qty: 2)

    row = CSV.parse(csv_body("promos"), headers: true).find { |r| r["code"] == "MV" }
    expect(row["mechanic"]).to eq("multivariant_percent")
    expect(row["tiers"]).to eq("2:0.08")
    expect(row["items"]).to eq("111:2|222:2")
  end
end
