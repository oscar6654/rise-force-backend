module Import
  # CSV headers (vcsi product_masters style):
  #   itemkey, desc1, desc2, brand_code, category_code, item_tier, abc_class,
  #   stock_uom, purchase_uom, selling_uom, items_per_case,
  #   it_barcode, cs_barcode, sw_barcode, item_cost, case_cost, tax, status
  class ProductsImporter < BaseImporter
    JOB_TYPE = :product_import

    private

    def import_row(row)
      key = (row["itemkey"] || row["sku"]).to_s.strip
      raise "itemkey is required" if key.blank?

      product = Product.find_or_initialize_by(sku: key)
      product.description  = (row["desc1"] || row["description"]).presence || product.description || key
      product.desc2        = row["desc2"].presence
      product.brand            = upsert_by_code(Brand, row["brand_code"], row["brand_name"]) if row["brand_code"].present?
      product.product_category = upsert_by_code(ProductCategory, row["category_code"], row["category_name"]) if row["category_code"].present?
      product.tier_code    = (row["item_tier"] || row["tier"]).presence
      product.abc_class    = row["abc_class"].presence
      product.stock_uom    = row["stock_uom"].presence
      product.purchase_uom = row["purchase_uom"].presence
      product.selling_uom  = row["selling_uom"].presence
      product.pcs_per_case = num(row["items_per_case"] || row["pcs_per_case"])
      product.it_barcode   = row["it_barcode"].presence
      product.cs_barcode   = row["cs_barcode"].presence
      product.sw_barcode   = row["sw_barcode"].presence
      product.item_cost    = num(row["item_cost"])
      product.case_cost    = num(row["case_cost"])
      product.tax_code     = row["tax"].presence
      product.status       = (row["status"].to_s.downcase.in?(%w[false 0 inactive discontinued]) ? :discontinued : :active) if row["status"].present?
      product.save!
    end

    # Normalize a numeric cell: spreadsheets export money with thousands
    # separators and padding (" 81,643.97 "), which won't cast to a decimal and
    # fails numericality. Strip spaces and commas; nil when blank.
    def num(value)
      s = value.to_s.strip.delete(",")
      # "-" / "—" / "N/A" etc. are spreadsheet placeholders for blank/zero — nil
      # them out (the cost columns allow nil) so they don't fail numericality.
      s =~ /\A-?\d*\.?\d+\z/ ? s : nil
    end

    # Brand/ProductCategory codes are unique case-insensitively, so match that
    # way (KOPIKO == kopiko) — otherwise a case difference from the sheet tries
    # to create a duplicate and fails "Code has already been taken". Only create
    # when the code is genuinely new.
    def upsert_by_code(model, code, name)
      code = code.to_s.strip
      model.where("lower(code) = ?", code.downcase).first ||
        model.create!(code: code, name: name.presence || code)
    end
  end
end
