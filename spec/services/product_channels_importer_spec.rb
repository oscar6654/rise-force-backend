require "rails_helper"

RSpec.describe Import::ProductChannelsImporter do
  let(:user) { create(:user) }
  let!(:coffee) { create(:product, sku: "SKU-COFFEE", description: "Coffee") }
  let!(:grocery) { create(:channel, code: "GROC", name: "Grocery") }

  def run(csv) = described_class.new(csv, user: user, filename: "map.csv").call

  it "upserts a mapping keyed by item_key + channel_code (idempotent)" do
    csv = "item_key,channel_code\nSKU-COFFEE,GROC\nSKU-COFFEE,GROC\n"
    log = run(csv)
    expect(log.processed_rows).to eq(2)
    expect(log.error_count).to eq(0)
    expect(ProductChannel.where(product: coffee, channel: grocery).count).to eq(1)
  end

  it "rejects rows whose item_key or channel_code is not in the masters" do
    csv = "item_key,channel_code\nNOPE,GROC\nSKU-COFFEE,ZZZ\n"
    log = run(csv)
    expect(log.error_count).to eq(2)
    expect(log.rejected_records_data.map { |r| r["error"] || r[:error] }.join).to match(/product master|channel master/)
    expect(ProductChannel.count).to eq(0)
  end

  it "removes a mapping when available is false" do
    ProductChannel.create!(product: coffee, channel: grocery)
    run("item_key,channel_code,available\nSKU-COFFEE,GROC,false\n")
    expect(ProductChannel.where(product: coffee, channel: grocery)).to be_empty
  end

  describe "Product.available_in_channel (channel-centric strict)" do
    let!(:sari) { create(:channel, code: "SARI", name: "Sari-Sari") }
    let!(:rice) { create(:product, sku: "SKU-RICE", description: "Rice") }

    it "shows only the mapped SKUs for a channel that has a curated list" do
      ProductChannel.create!(product: coffee, channel: grocery) # grocery list = [coffee]

      expect(Product.available_in_channel(grocery.id).pluck(:sku)).to contain_exactly("SKU-COFFEE")
    end

    it "falls back to all SKUs for a channel with no list yet (unconfigured)" do
      ProductChannel.create!(product: coffee, channel: grocery) # grocery configured, sari is not

      expect(Product.available_in_channel(sari.id).pluck(:sku)).to contain_exactly("SKU-COFFEE", "SKU-RICE")
    end
  end
end
