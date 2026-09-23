require "rails_helper"

RSpec.describe "Promos console", type: :request do
  include Warden::Test::Helpers
  let(:user) { create(:user, branch_id: nil) }

  before do
    allow_any_instance_of(User).to receive(:has_permission?).and_return(true)
    login_as(user, scope: :user)
  end

  it "renders the new form with the volume-tier editor" do
    get new_promo_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Volume tiers")
    expect(response.body).to include("promo[config_tiers]")
    expect(response.body).to include('data-mechanics="tiered_discount"')
  end

  it "creates a tiered promo from the form's basis + compact tiers" do
    post promos_path, params: {
      promo: { code: "UI-TIER", name: "UI Volume", mechanic_type: "tiered_discount", status: "active",
               config_basis: "pieces", config_tiers: "18:0.04|72:0.07" },
    }
    expect(response).to have_http_status(:redirect)
    promo = Promo.find_by(code: "UI-TIER")
    expect(promo.config["basis"]).to eq("pieces")
    expect(promo.config["tiers"]).to eq([{ "min" => 18.0, "rate" => 0.04 }, { "min" => 72.0, "rate" => 0.07 }])
  end

  it "renders the combo editor and creates a combo_percent promo from the form" do
    a = create(:product, sku: "CA", it_barcode: "7770001")
    b = create(:product, sku: "CB", it_barcode: "7770002")

    get new_promo_path
    expect(response.body).to include('data-mechanics="combo_percent"')
    expect(response.body).to include("promo[config_rate]")

    post promos_path, params: {
      promo: {
        code: "UI-COMBO", name: "UI Combo", mechanic_type: "combo_percent", status: "active",
        config_rate: "10", # percent -> stored as 0.10
        promo_lines_attributes: {
          "0" => { role: "qualifying", it_barcode: "7770001", min_qty: "24" },
          "1" => { role: "qualifying", it_barcode: "7770002", min_qty: "12" },
        },
      },
    }
    expect(response).to have_http_status(:redirect)
    promo = Promo.find_by(code: "UI-COMBO")
    expect(promo.config["rate"]).to eq(0.10)
    expect(promo.promo_lines.where(role: :qualifying).pluck(:it_barcode, :min_qty)).to contain_exactly(["7770001", 24], ["7770002", 12])
  end

  it "serves an example CSV that imports without edits (round-trip)" do
    create(:product, sku: "S1", it_barcode: "4800016641")
    create(:product, sku: "S2", it_barcode: "4801234567")
    create(:channel, code: "AAA", name: "Channel A")
    create(:channel, code: "BBB", name: "Channel B")

    get sample_import_path("promos")
    expect(response).to have_http_status(:ok)
    expect(response.content_type).to include("text/csv")
    expect(response.body).to include("tiered_discount").and include("18:0.04|72:0.07")

    log = Import::PromosImporter.new(response.body, user: user, filename: "e.csv").call
    expect(log.error_count).to eq(0)
    expect(Promo.count).to eq(10) # one example row per mechanic + a multi-channel spend + combo
    expect(Promo.distinct.pluck(:mechanic_type)).to include("bundle_price", "free_goods", "discount_percent", "combo_percent")
    # the multi-channel example (channel_code "AAA;BBB") becomes two eligibility rows
    expect(Promo.find_by(code: "HFSWS-SPEND").promo_eligibilities.map { |e| e.channel.code }).to contain_exactly("AAA", "BBB")
  end

  it "bulk-imports promos through the shared import flow" do
    create(:product, sku: "P1", it_barcode: "4800000001")
    csv = "code,name,mechanic,basis,it_barcode,tiers\nUP-1,Uploaded,tiered_discount,pieces,4800000001,24:0.05|48:0.08\n"
    file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "promos.csv")
    post imports_path("promos"), params: { file: file }
    expect(response).to have_http_status(:redirect)
    expect(Promo.find_by(code: "UP-1").config["tiers"].size).to eq(2)
  end
end
