require "rails_helper"

RSpec.describe Import::PromosImporter do
  let(:user) { create(:user) }
  # Two item_keys sharing one barcode → a barcode-scoped promo covers both.
  let!(:kop1) { create(:product, sku: "KOP-10s", it_barcode: "4800016641", pcs_per_case: 12) }
  let!(:kop2) { create(:product, sku: "KOP-6s", it_barcode: "4800016641", pcs_per_case: 24) }
  let!(:sari) { create(:channel, code: "SARI", name: "Sari-Sari") }

  def run(csv) = described_class.new(csv, user: user, filename: "promos.csv").call

  it "imports a tiered percent-by-pieces promo (4% 18–71 pc, 7% 72+)" do
    csv = "code,name,mechanic,basis,it_barcode,tiers,channel_code\n" \
          "KOP-VOL,Kopiko volume,tiered_discount,pieces,4800016641,18:0.04|72:0.07,SARI\n"
    log = run(csv)
    expect(log.error_count).to eq(0)

    promo = Promo.find_by(code: "KOP-VOL")
    expect(promo.mechanic_type).to eq("tiered_discount")
    expect(promo.config["basis"]).to eq("pieces")
    expect(promo.config["tiers"]).to eq([{ "min" => 18.0, "rate" => 0.04 }, { "min" => 72.0, "rate" => 0.07 }])
    expect(promo.promo_lines.where(role: :qualifying).first.it_barcode).to eq("4800016641")
    expect(promo.promo_eligibilities.first.channel).to eq(sari)
  end

  it "imports a spend-threshold promo (₱100 ≥₱1200, ₱300 ≥₱3000, whole order)" do
    csv = "code,name,mechanic,basis,tiers\nSPEND,Spend save,tiered_discount,amount,1200:100|3000:300\n"
    run(csv)
    promo = Promo.find_by(code: "SPEND")
    expect(promo.config["tiers"]).to eq([{ "min" => 1200.0, "amount" => 100.0 }, { "min" => 3000.0, "amount" => 300.0 }])
    expect(promo.promo_lines).to be_empty # whole-order
  end

  it "imports a buy-x-get-y promo by barcode" do
    csv = "code,name,mechanic,it_barcode,min_qty,reward_qty\nBXGY,Buy 60 get 1,buy_x_get_y,4800016641,60,1\n"
    run(csv)
    promo = Promo.find_by(code: "BXGY")
    expect(promo.promo_lines.where(role: :qualifying).first.min_qty).to eq(60)
    expect(promo.promo_lines.where(role: :reward).first.reward_qty).to eq(1)
  end

  it "upserts on code and rejects unknown barcodes / mechanics" do
    run("code,name,mechanic,basis,it_barcode,tiers\nKOP-VOL,V1,tiered_discount,pieces,4800016641,18:0.04\n")
    run("code,name,mechanic,basis,it_barcode,tiers\nKOP-VOL,V2,tiered_discount,pieces,4800016641,10:0.05\n")
    expect(Promo.where(code: "KOP-VOL").count).to eq(1)
    expect(Promo.find_by(code: "KOP-VOL").name).to eq("V2")

    log = run("code,name,mechanic,basis,it_barcode,tiers\nBAD,x,tiered_discount,pieces,9999999,18:0.04\nBAD2,x,nope,,,\n")
    expect(log.error_count).to eq(2)
  end
end
