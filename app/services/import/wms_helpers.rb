module Import
  # Shared cell parsers for the WMS importers (keeps each importer focused on its
  # own columns). Included into the WMS importer subclasses.
  module WmsHelpers
    TRUE_VALUES = %w[1 true yes y t active on].freeze

    def num(value)
      s = value.to_s.strip.delete(",")
      s =~ /\A-?\d*\.?\d+\z/ ? s : nil
    end

    def truthy(value, default: false)
      return default if value.nil? || value.to_s.strip.empty?

      TRUE_VALUES.include?(value.to_s.strip.downcase)
    end

    # "A;B" / "A,B" / "A|B" -> ["A","B"] (uppercased, blanks dropped).
    def split_list(value, upcase: false)
      Array(value.to_s.split(/[;,|]/)).map { |s| upcase ? s.strip.upcase : s.strip }.reject(&:blank?)
    end

    def warehouse_for!(code)
      wh = Warehouse.find_by("lower(whs_code) = ?", code.to_s.strip.downcase)
      raise "Unknown warehouse_code '#{code}'" unless wh

      wh
    end

    # Resolve a product from an itemkey (sku) or a barcode (representative SKU).
    def product_for(sku: nil, it_barcode: nil)
      if sku.present?
        p = Product.find_by("lower(sku) = ?", sku.to_s.strip.downcase)
        return p if p
      end
      it_barcode.present? ? Product.representative_for(it_barcode.to_s.strip) : nil
    end

    # Convert a quantity in the given uom to canonical pieces.
    def to_pieces(qty, uom, product)
      q = num(qty).to_d
      uom.to_s.strip.downcase.in?(%w[case cs case_uom cases]) ? q * (product.pcs_per_case || 1) : q
    end
  end
end
