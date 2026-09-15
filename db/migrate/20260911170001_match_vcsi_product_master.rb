class MatchVcsiProductMaster < ActiveRecord::Migration[8.1]
  def up
    change_table :products, bulk: true do |t|
      # Descriptions / classification (vcsi product_masters)
      t.string  :desc2
      t.string  :ordering_unit
      t.string  :brand_form
      t.string  :variant_code
      # UOMs (replace the earlier case_uom/pc_uom)
      t.string  :stock_uom
      t.string  :purchase_uom
      t.string  :selling_uom
      # Barcodes (it_barcode / cs_barcode already exist)
      t.string  :sw_barcode
      # Packaging factors
      t.integer :casestatfactor
      t.integer :casesperpallet
      t.integer :layersperpallet
      t.integer :shrinkwraps_per_case
      t.integer :items_per_shrinkwrap
      t.decimal :caseheight, precision: 10, scale: 4
      t.decimal :caseweight, precision: 10, scale: 4
      t.decimal :casevolume, precision: 10, scale: 4
      # Misc vcsi attributes
      t.string  :slideoutcode
      t.string  :ovsoldcostmethod
      t.string  :msq
      t.string  :nspacksize
      t.string  :nspacktype
    end

    add_index :products, :sw_barcode

    # Remove the confusing custom fields (tiering is item_tier -> product_tier).
    remove_column :products, :must_stock_type
    remove_column :products, :case_uom
    remove_column :products, :pc_uom
  end

  def down
    change_table :products, bulk: true do |t|
      t.remove :desc2, :ordering_unit, :brand_form, :variant_code, :stock_uom,
               :purchase_uom, :selling_uom, :sw_barcode, :casestatfactor,
               :casesperpallet, :layersperpallet, :shrinkwraps_per_case,
               :items_per_shrinkwrap, :caseheight, :caseweight, :casevolume,
               :slideoutcode, :ovsoldcostmethod, :msq, :nspacksize, :nspacktype
      t.integer :must_stock_type
      t.string  :case_uom
      t.string  :pc_uom
    end
  end
end
