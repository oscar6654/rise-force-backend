require "rails_helper"

RSpec.describe ManagerInsights, "#by_channel" do
  let(:month) { Date.current.beginning_of_month }
  let(:hfs)   { create(:channel, name: "HFS SMALL") }
  let(:ka)    { create(:channel, name: "KA WS LARGE") }

  # Stores are matched to a channel by vcsi_customer_ref (the stable identity),
  # NOT by seller assignment — so reassigned/new/closed stores still reconcile.
  before do
    create(:store, channel: hfs, vcsi_customer_ref: "R1")
    create(:store, channel: hfs, vcsi_customer_ref: "R2")
    create(:store, channel: ka,  vcsi_customer_ref: "R3")

    client = instance_double(VcsiRise::Client)
    allow(VcsiRise::Client).to receive(:new).and_return(client)
    allow(client).to receive(:sales_daily).and_return([])
    allow(client).to receive(:store_sku_sellout).and_return([])

    # Current month: HFS = R1+R2 = 1500 (2 active), KA = R3 = 2000 (1 active).
    allow(client).to receive(:store_sellout).with(hash_including(month: month)).and_return([
      { "customer_id" => "R1", "sellout" => "1000.0" },
      { "customer_id" => "R2", "sellout" => "500.0" },
      { "customer_id" => "R3", "sellout" => "2000.0" },
    ])
    # Last month: HFS = 800, KA = 2500.
    allow(client).to receive(:store_sellout).with(hash_including(month: month - 1.month)).and_return([
      { "customer_id" => "R1", "sellout" => "800.0" },
      { "customer_id" => "R3", "sellout" => "2500.0" },
    ])
    # Year ago: only HFS R1 = 600 sold (KA has no year-ago row → new to channel).
    allow(client).to receive(:store_sellout).with(hash_including(month: month - 12.months)).and_return([
      { "customer_id" => "R1", "sellout" => "600.0" },
    ])
  end

  subject(:channels) { described_class.new(rep_codes: ["REP1"]).call[:by_channel] }

  it "aggregates sellout per channel, ranked high to low" do
    expect(channels.map { |c| c[:name] }).to eq(["KA WS LARGE", "HFS SMALL"])
    expect(channels.map { |c| c[:sellout] }).to eq([2000.0, 1500.0])
  end

  it "computes MoM and YoY growth, with nil when there is no comparable base" do
    hfs_row = channels.find { |c| c[:name] == "HFS SMALL" }
    ka_row  = channels.find { |c| c[:name] == "KA WS LARGE" }

    expect(hfs_row[:mom]).to eq(87.5)   # (1500-800)/800
    expect(hfs_row[:yoy]).to eq(150.0)  # (1500-600)/600
    expect(ka_row[:mom]).to eq(-20.0)   # (2000-2500)/2500
    expect(ka_row[:yoy]).to be_nil      # no year-ago base
  end

  it "counts active stores this month vs the same month last year" do
    hfs_row = channels.find { |c| c[:name] == "HFS SMALL" }
    ka_row  = channels.find { |c| c[:name] == "KA WS LARGE" }

    expect(hfs_row[:active_stores]).to eq(2)
    expect(hfs_row[:active_stores_ya]).to eq(1) # only R1 sold a year ago
    expect(ka_row[:active_stores]).to eq(1)
    expect(ka_row[:active_stores_ya]).to eq(0)  # new door this year
  end

  it "reconciles the per-channel sellout to the feed total" do
    expect(channels.sum { |c| c[:sellout] }).to eq(3500.0)
  end
end
