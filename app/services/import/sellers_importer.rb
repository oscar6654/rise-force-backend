module Import
  # Bulk-loads the SELLER master, keyed on seller_code (upsert + MERGE: a blank
  # cell leaves the existing value untouched, so a partial re-upload updates only
  # the columns it provides). CSV headers (all optional except seller_code;
  # branch_code required for NEW sellers unless a default branch is supplied):
  #   seller_code, name, branch_code, status, section, vcsi_sales_rep_ref,
  #   supervisor_name, gsm_name, om_name, sales_target,
  #   diser_code, diser_name, primary_seller_code, manager_codes, pin, diser_pin
  #
  # status: active | suspended | inactive (blank = keep / default active for new).
  # vcsi_sales_rep_ref is the JOIN KEY to vcsi_rise (sales_rep) — it drives
  # sellout, targets and the manager By-channel insight, so keep it accurate.
  # primary_seller_code links a rep's extra branch/code record to a primary (one
  # login group). manager_codes = ';'-separated Manager codes (replaces the
  # seller's manager assignment). pin / diser_pin: blank keeps the existing PIN.
  class SellersImporter < BaseImporter
    JOB_TYPE = :seller_import

    def initialize(*args, default_branch: nil, **kwargs)
      super(*args, **kwargs)
      @default_branch = default_branch
    end

    private

    def import_row(row)
      code = row["seller_code"].to_s.strip
      raise "seller_code is required" if code.blank?

      seller = Seller.find_or_initialize_by(seller_code: code)
      assign_branch(seller, row)

      set(seller, :name, row["name"])
      seller.name = code if seller.name.blank? # new rows must have a name
      set_status(seller, row["status"])
      set(seller, :section, row["section"])
      set(seller, :vcsi_sales_rep_ref, row["vcsi_sales_rep_ref"])
      set(seller, :supervisor_name, row["supervisor_name"])
      set(seller, :gsm_name, row["gsm_name"])
      set(seller, :om_name, row["om_name"])
      seller.sales_target = clean_num(row["sales_target"]) if row["sales_target"].present?
      set(seller, :diser_code, row["diser_code"])
      set(seller, :diser_name, row["diser_name"])
      set_primary(seller, row["primary_seller_code"])

      # PINs go through has_secure_password; blank leaves the existing one.
      seller.pin = row["pin"].to_s.strip if row["pin"].present?
      seller.diser_pin = row["diser_pin"].to_s.strip if row["diser_pin"].present?

      seller.status ||= :active
      seller.save!
      set_managers(seller, row) # M2M; only when the column carries codes
    end

    def set(seller, attr, value)
      seller.public_send("#{attr}=", value.to_s.strip) if value.present?
    end

    def set_status(seller, value)
      v = value.to_s.strip.downcase
      return if v.blank?
      raise "unknown status '#{value}' (use #{Seller.statuses.keys.join('/')})" unless Seller.statuses.key?(v)

      seller.status = v
    end

    # Link to the primary seller of a login group (resolves by code). Must already
    # exist in the master — put primaries before their secondaries in the sheet.
    def set_primary(seller, code)
      return if code.to_s.strip.blank?

      primary = Seller.find_by(seller_code: code.to_s.strip)
      raise "unknown primary_seller_code '#{code}'" if primary.nil?
      raise "a seller can't be its own primary (#{seller.seller_code})" if primary.seller_code == seller.seller_code

      seller.primary_seller = primary
    end

    # Replace the seller's manager assignment from a ';'-separated code list.
    # Blank/absent leaves the existing assignment (merge semantics).
    def set_managers(seller, row)
      codes = row["manager_codes"].to_s.split(/[;,|]/).map(&:strip).reject(&:blank?)
      return if codes.empty?

      managers = codes.map do |c|
        Manager.find_by("lower(code) = ?", c.downcase) || (raise "unknown manager_code '#{c}'")
      end
      seller.managers = managers
    end

    def assign_branch(seller, row)
      if row["branch_code"].present?
        branch = Branch.find_by(code: row["branch_code"])
        raise "unknown branch #{row['branch_code']}" if branch.nil?

        seller.branch = branch
      elsif seller.new_record?
        raise "branch_code is required for new seller #{seller.seller_code}" if @default_branch.nil?

        seller.branch = @default_branch
      end
    end

    # Spreadsheet money carries thousands separators + padding ("1,000,000 ").
    def clean_num(value)
      s = value.to_s.gsub(/[,\s]/, "")
      s.match?(/\A-?\d*\.?\d+\z/) ? s : nil
    end
  end
end
