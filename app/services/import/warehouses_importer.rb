module Import
  # CSV headers: whs_code, wh_name, branch_code, address, status,
  #              wms_enabled, allocation_strategy
  # Upsert by whs_code.
  class WarehousesImporter < BaseImporter
    include WmsHelpers
    JOB_TYPE = :warehouse_import

    private

    def import_row(row)
      code = row["whs_code"].to_s.strip
      raise "whs_code is required" if code.blank?

      wh = Warehouse.find_or_initialize_by(whs_code: code)
      wh.wh_name = row["wh_name"].presence || wh.wh_name || code
      wh.branch  = Branch.find_by("lower(code) = ?", row["branch_code"].to_s.strip.downcase) if row["branch_code"].present?
      wh.address = row["address"].presence if row.key?("address")
      wh.status  = (row["status"].to_s.downcase == "inactive" ? :inactive : :active) if row["status"].present?
      wh.wms_enabled = truthy(row["wms_enabled"], default: wh.wms_enabled) if row.key?("wms_enabled")
      wh.allocation_strategy = allocation_strategy(row["allocation_strategy"]) if row["allocation_strategy"].present?
      wh.save!
    end

    def allocation_strategy(value)
      value.to_s.strip.downcase.start_with?("zone") ? :zone_per_picker : :brand_per_picker
    end
  end
end
