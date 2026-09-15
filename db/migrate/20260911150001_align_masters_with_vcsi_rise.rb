class AlignMastersWithVcsiRise < ActiveRecord::Migration[8.1]
  def change
    # --- Product: barcodes, costs, variant/abc/tax (match vcsi product_masters) ---
    change_table :products, bulk: true do |t|
      t.string  :it_barcode        # item barcode
      t.string  :cs_barcode        # case/carton barcode
      t.decimal :item_cost, precision: 15, scale: 2
      t.decimal :case_cost, precision: 15, scale: 2
      t.string  :variant_name
      t.string  :abc_class         # A/B/C movement class
      t.string  :tax_code
    end
    add_index :products, :it_barcode
    add_index :products, :cs_barcode

    # --- Store (customer master): direct seller assignment + segmentation ---
    change_table :stores, bulk: true do |t|
      t.references :seller, foreign_key: true, null: true  # direct sales-rep assignment
      t.string :segment
      t.string :chain
      t.string :sub_chain
      t.string :distribution_type
      t.string :tin
    end

    # --- Seller: hierarchy + target (match vcsi seller_masters) ---
    change_table :sellers, bulk: true do |t|
      t.string  :supervisor_name
      t.string  :gsm_name          # General Sales Manager
      t.string  :om_name           # Operations Manager
      t.decimal :sales_target, precision: 15, scale: 2
    end

    # --- Warehouse master ---
    create_table :warehouses do |t|
      t.references :branch, foreign_key: true, null: true
      t.string  :whs_code, null: false
      t.string  :wh_name, null: false
      t.string  :address
      t.integer :status, null: false, default: 0
      t.timestamps
    end
    add_index :warehouses, :whs_code, unique: true
  end
end
