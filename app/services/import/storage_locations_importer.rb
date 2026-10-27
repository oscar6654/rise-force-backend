module Import
  # CSV headers: warehouse_code, loc_code, name, zone, aisle, bay, level,
  #   loc_type, pickable, allow_mixed_lots, slot_capacity, pick_sequence,
  #   allowed_abc_classes, allowed_brand_codes, status
  # Upsert by [warehouse, loc_code]. Acceptance rules drive putaway, so
  # allowed_abc_classes ("A;B") and allowed_brand_codes resolve to arrays.
  class StorageLocationsImporter < BaseImporter
    include WmsHelpers
    JOB_TYPE = :storage_location_import

    LOC_TYPES = StorageLocation.loc_types.keys.freeze

    private

    def import_row(row)
      wh = warehouse_for!(row["warehouse_code"])
      code = row["loc_code"].to_s.strip
      raise "loc_code is required" if code.blank?

      loc = StorageLocation.find_or_initialize_by(warehouse: wh, loc_code: code)
      loc.name  = row["name"].presence if row.key?("name")
      loc.zone  = row["zone"].presence if row.key?("zone")
      loc.aisle = row["aisle"].presence if row.key?("aisle")
      loc.bay   = row["bay"].presence if row.key?("bay")
      loc.level = row["level"].presence if row.key?("level")
      loc.loc_type = normalize_loc_type(row["loc_type"]) if row["loc_type"].present?
      loc.pickable = truthy(row["pickable"], default: loc.new_record? ? true : loc.pickable) if row.key?("pickable")
      loc.allow_mixed_lots = truthy(row["allow_mixed_lots"], default: loc.allow_mixed_lots) if row.key?("allow_mixed_lots")
      loc.slot_capacity = (num(row["slot_capacity"]) || loc.slot_capacity || 1).to_i if row.key?("slot_capacity")
      loc.pick_sequence = (num(row["pick_sequence"]) || loc.pick_sequence || 0).to_i if row.key?("pick_sequence")
      loc.allowed_abc_classes = split_list(row["allowed_abc_classes"], upcase: true) if row.key?("allowed_abc_classes")
      loc.allowed_brand_ids = brand_ids(row["allowed_brand_codes"]) if row.key?("allowed_brand_codes")
      loc.status = (row["status"].to_s.downcase == "inactive" ? :inactive : :active) if row["status"].present?
      loc.save!
    end

    def normalize_loc_type(value)
      v = value.to_s.strip.downcase.tr(" -", "__")
      LOC_TYPES.include?(v) ? v : :pick_rack
    end

    def brand_ids(codes)
      split_list(codes).filter_map do |code|
        Brand.where("lower(code) = ?", code.downcase).pick(:id)
      end
    end
  end
end
