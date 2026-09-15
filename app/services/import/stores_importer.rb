module Import
  # CSV headers (all optional except store_code; branch_code required for NEW
  # stores unless a default branch is supplied):
  #   store_code, name, owner_name, address, contact_number, latitude, longitude,
  #   branch_code, channel_code, category, vcsi_customer_ref,
  #   segment, chain, sub_chain, distribution_type, tin,
  #   seller_code, route_code, route_name,
  #   visit_frequency, week_pattern, visit_day, visit_sequence
  #
  # ROUTE PLAN: a store reaches a seller's call list via its ROUTE (route_code →
  # a Route owned by seller_code; created if missing). The visit block
  # (visit_frequency f2|f4, week_pattern every_week|weeks_1_3|weeks_2_4,
  # visit_day mon..sat, visit_sequence) is that store's plan within the route.
  #
  # UPSERT + MERGE: keyed on store_code — a new code creates, an existing code
  # updates. A blank cell leaves the existing value untouched, so a partial
  # re-upload updates only the columns it provides and never wipes data (e.g.
  # re-uploading without vcsi_customer_ref keeps the link already set).
  class StoresImporter < BaseImporter
    JOB_TYPE = :store_import

    IDENTITY_ATTRS = %w[segment chain sub_chain distribution_type tin].freeze

    def initialize(*args, default_branch: nil, **kwargs)
      super(*args, **kwargs)
      @default_branch = default_branch
    end

    private

    def import_row(row)
      code = row["store_code"].to_s.strip
      raise "store_code is required" if code.blank?

      store = Store.find_or_initialize_by(store_code: code)

      assign_branch(store, row)

      set(store, :name, row["name"])
      store.name = code if store.name.blank? # new rows must have a name
      set(store, :owner_name, row["owner_name"])
      set(store, :address, row["address"])
      set(store, :contact_number, row["contact_number"])
      set(store, :latitude, row["latitude"])
      set(store, :longitude, row["longitude"])
      set(store, :category_code, row["category"]) # resolves/creates StoreCategory
      set(store, :vcsi_customer_ref, row["vcsi_customer_ref"]) # vcsi_rise customer_id link
      IDENTITY_ATTRS.each { |attr| set(store, attr, row[attr]) }
      # These three are lowercase enums (f2/f4, every_week…, mon…sat) — accept
      # any case from the sheet (Wed, F4, Every_Week) by normalizing here.
      set_enum(store, :visit_frequency, row["visit_frequency"])
      set_enum(store, :week_pattern, row["week_pattern"])
      set_enum(store, :visit_day, row["visit_day"])
      set(store, :visit_sequence, row["visit_sequence"])

      store.channel = Channel.find_by(code: row["channel_code"]) if row["channel_code"].present?
      assign_seller_and_route(store, row)

      apply_new_record_defaults(store) if store.new_record?

      store.save!
    end

    # Tag the servicing seller (direct, for attribution) and put the store on a
    # route (which is what the seller's call list reads). The route is created
    # for the seller when it doesn't exist yet.
    def assign_seller_and_route(store, row)
      seller =
        if row["seller_code"].present?
          Seller.find_by(seller_code: row["seller_code"].to_s.strip) ||
            (raise "unknown seller_code #{row['seller_code']}")
        end
      store.seller = seller if seller

      return if row["route_code"].blank?

      route = Route.find_by(code: row["route_code"].to_s.strip)
      if route.nil?
        owner = seller || store.route&.seller
        raise "route #{row['route_code']} is new — add a seller_code so it can be created" if owner.nil?

        route = Route.create!(code: row["route_code"].to_s.strip,
                              name: row["route_name"].presence || row["route_code"].to_s.strip,
                              seller: owner, branch: store.branch || owner.branch)
      end
      store.route = route
    end

    # Assign only when the CSV provides a value (merge semantics).
    def set(store, attr, value)
      store.public_send("#{attr}=", value.to_s.strip) if value.present?
    end

    # Same as #set but case-insensitive, for the lowercase enum columns.
    def set_enum(store, attr, value)
      store.public_send("#{attr}=", value.to_s.strip.downcase) if value.present?
    end

    def assign_branch(store, row)
      if row["branch_code"].present?
        branch = Branch.find_by(code: row["branch_code"])
        raise "unknown branch #{row['branch_code']}" if branch.nil?

        store.branch = branch
      elsif store.new_record?
        raise "branch_code is required for new store #{store.store_code}" if @default_branch.nil?

        store.branch = @default_branch
      end
    end

    def apply_new_record_defaults(store)
      store.status          ||= :active
      store.visit_frequency ||= "f4"
      store.week_pattern    ||= "every_week"
    end
  end
end
