require "rails_helper"

RSpec.describe Import::ProductsImporter do
  let(:user) { create(:user) }

  it "imports the pallet/pack/dimension columns and abc_class" do
    csv = <<~CSV
      itemkey,desc1,abc_class,items_per_case,items_per_shrinkwrap,shrinkwraps_per_case,casesperpallet,layersperpallet,casestatfactor,caseheight,caseweight,casevolume
      PAL-1,Palletised SKU,A,12,6,2,80,5,1,0.25,5.4,0.018
    CSV
    described_class.new(csv, user: user).call

    p = Product.find_by(sku: "PAL-1")
    expect(p.pcs_per_case).to eq(12)
    expect(p.items_per_shrinkwrap).to eq(6)
    expect(p.shrinkwraps_per_case).to eq(2)
    expect(p.casesperpallet).to eq(80)
    expect(p.layersperpallet).to eq(5)
    expect(p.casestatfactor).to eq(1)
    expect(p.caseheight.to_f).to eq(0.25)
    expect(p.caseweight.to_f).to eq(5.4)
    expect(p.casevolume.to_f).to eq(0.018)
    expect(p.abc_class).to eq("A")
  end

  it "does not wipe existing pallet config when those columns are absent" do
    create(:product, sku: "KEEP-1", casesperpallet: 60, layersperpallet: 4)
    csv = "itemkey,desc1\nKEEP-1,Renamed\n"
    described_class.new(csv, user: user).call

    p = Product.find_by(sku: "KEEP-1")
    expect(p.description).to eq("Renamed")
    expect(p.casesperpallet).to eq(60) # preserved
    expect(p.layersperpallet).to eq(4)
  end
end
