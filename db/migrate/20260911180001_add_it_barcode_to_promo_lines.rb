class AddItBarcodeToPromoLines < ActiveRecord::Migration[8.1]
  def change
    # Promo/assortment target an IT barcode (which maps to many item_keys/SKUs),
    # so one selection auto-applies to every product sharing that barcode.
    add_column :promo_lines, :it_barcode, :string
    add_index :promo_lines, :it_barcode
  end
end
