require "rails_helper"

RSpec.describe Import::SellersImporter do
  let(:branch) { create(:branch, code: "HO") }

  def run(csv)
    described_class.new(csv, user: nil, filename: "t.csv", default_branch: branch).call
  end

  it "creates a seller and resolves branch + key master fields" do
    log = run("seller_code,name,branch_code,status,section,vcsi_sales_rep_ref,sales_target\n" \
              "SLR-1,Juan,HO,active,KA,538614,\"1,500,000\"\n")
    expect(log.error_count).to eq(0)
    s = Seller.find_by(seller_code: "SLR-1")
    expect(s.name).to eq("Juan")
    expect(s.branch).to eq(branch)
    expect(s.section).to eq("KA")
    expect(s.vcsi_sales_rep_ref).to eq("538614")
    expect(s.sales_target).to eq(1_500_000)
    expect(s).to be_active
  end

  it "merges: blank cells keep existing, and a new code needs a branch" do
    run("seller_code,name,branch_code,vcsi_sales_rep_ref\nSLR-1,Juan,HO,538614\n")
    run("seller_code,name,branch_code\nSLR-1,Juan Cruz,HO\n") # omits vcsi ref
    expect(Seller.find_by(seller_code: "SLR-1").vcsi_sales_rep_ref).to eq("538614")

    log = run("seller_code,name\nSLR-NEW,NoBranch\n")
    expect(log.error_count).to eq(0) # default_branch supplied by the controller path
    expect(Seller.find_by(seller_code: "SLR-NEW").branch).to eq(branch)
  end

  it "sets status and rejects an unknown status" do
    run("seller_code,name,branch_code,status\nSLR-1,Juan,HO,inactive\n")
    expect(Seller.find_by(seller_code: "SLR-1")).to be_inactive
    log = run("seller_code,name,branch_code,status\nSLR-2,Ana,HO,retired\n")
    expect(log.error_count).to eq(1)
    expect(log.rejected_records_data.first.to_json).to match(/status/)
  end

  it "links a secondary code to its primary (login group)" do
    run("seller_code,name,branch_code\nSLR-1,Juan,HO\n")
    run("seller_code,name,branch_code,primary_seller_code\nSLR-1B,Juan B2,HO,SLR-1\n")
    expect(Seller.find_by(seller_code: "SLR-1B").primary_seller).to eq(Seller.find_by(seller_code: "SLR-1"))

    log = run("seller_code,name,branch_code,primary_seller_code\nSLR-9,X,HO,NOPE\n")
    expect(log.error_count).to eq(1)
    expect(log.rejected_records_data.first.to_json).to match(/primary_seller_code/)
  end

  it "assigns managers from a semicolon list and rejects an unknown code" do
    m1 = Manager.create!(code: "MGR-A", name: "A")
    m2 = Manager.create!(code: "MGR-B", name: "B")
    run("seller_code,name,branch_code,manager_codes\nSLR-1,Juan,HO,MGR-A;MGR-B\n")
    expect(Seller.find_by(seller_code: "SLR-1").managers).to contain_exactly(m1, m2)

    log = run("seller_code,name,branch_code,manager_codes\nSLR-2,Ana,HO,MGR-A;NOPE\n")
    expect(log.error_count).to eq(1)
  end

  it "sets the PIN only when provided (blank keeps the existing one)" do
    run("seller_code,name,branch_code,pin\nSLR-1,Juan,HO,1234\n")
    s = Seller.find_by(seller_code: "SLR-1")
    expect(s.authenticate_pin("1234")).to be_truthy
    run("seller_code,name,branch_code\nSLR-1,Juan,HO\n") # no pin column
    expect(s.reload.authenticate_pin("1234")).to be_truthy
  end
end
