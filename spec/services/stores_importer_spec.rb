require "rails_helper"

RSpec.describe Import::StoresImporter do
  let(:branch) { create(:branch, code: "HO") }

  def run(csv)
    described_class.new(csv, user: nil, filename: "t.csv", default_branch: branch).call
  end

  it "creates a new store from a code and resolves category + vcsi link" do
    log = run("store_code,name,category,vcsi_customer_ref,branch_code\nS1,Nena Store,gold,CA_111,HO\n")
    expect(log.processed_rows).to eq(1)
    expect(log.error_count).to eq(0)
    store = Store.find_by(store_code: "S1")
    expect(store.name).to eq("Nena Store")
    expect(store.category).to eq("gold")
    expect(store.vcsi_customer_ref).to eq("CA_111")
  end

  it "updates an existing code instead of duplicating" do
    run("store_code,name,owner_name,branch_code\nS1,Nena Store,Nena,HO\n")
    log = run("store_code,owner_name,branch_code\nS1,Nena Reyes,HO\n")
    expect(log.error_count).to eq(0)
    expect(Store.where(store_code: "S1").count).to eq(1)
    expect(Store.find_by(store_code: "S1").owner_name).to eq("Nena Reyes")
  end

  it "preserves existing values for blank cells (never wipes the vcsi link)" do
    run("store_code,category,vcsi_customer_ref,branch_code\nS1,gold,CA_111,HO\n")
    run("store_code,owner_name,branch_code\nS1,Nena,HO\n") # omits category + vcsi_customer_ref
    store = Store.find_by(store_code: "S1")
    expect(store.category).to eq("gold")
    expect(store.vcsi_customer_ref).to eq("CA_111")
  end

  it "rejects a row with no store_code" do
    log = run("store_code,name,branch_code\n,No Code,HO\n")
    expect(log.error_count).to eq(1)
  end
it "tags the seller and creates the route (route plan) so the store hits the call list" do
  seller = create(:seller, branch: branch, seller_code: "SLR-9")
  log = run("store_code,name,branch_code,seller_code,route_code,route_name,visit_frequency,week_pattern,visit_day,visit_sequence\nS9,Nena,HO,SLR-9,R-1,QC North,f2,weeks_1_3,wed,2\n")
  expect(log.error_count).to eq(0)
  store = Store.find_by(store_code: "S9")
  expect(store.seller).to eq(seller)
  route = Route.find_by(code: "R-1")
  expect(route).to be_present
  expect(route.seller).to eq(seller)
  expect(route.name).to eq("QC North")
  expect(store.route).to eq(route)
  expect(store.visit_frequency).to eq("f2")
  expect(store.week_pattern).to eq("weeks_1_3")
  expect(store.visit_day).to eq("wed")
  expect(store.visit_sequence).to eq(2)
end

it "reuses an existing route and rejects an unknown seller_code" do
  seller = create(:seller, branch: branch, seller_code: "SLR-A")
  route = Route.create!(code: "R-EXIST", name: "Beat", seller: seller, branch: branch)
  run("store_code,name,branch_code,route_code\nS10,X,HO,R-EXIST\n")
  expect(Store.find_by(store_code: "S10").route).to eq(route)
  expect(Route.where(code: "R-EXIST").count).to eq(1)

  log = run("store_code,name,branch_code,seller_code\nS11,Y,HO,NOPE\n")
  expect(log.error_count).to eq(1)
end

it "requires a seller_code to create a brand-new route" do
  log = run("store_code,name,branch_code,route_code\nS12,Z,HO,R-NEW\n")
  expect(log.error_count).to eq(1)
  expect(log.rejected_records_data.first.to_json).to match(/seller_code/)
end

end
