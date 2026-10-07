module Import
  # Parses the execution-evidence CSV (result file) into a campaign's evidence,
  # matched by header name: Store Name (→ CU_#### code), Promotion Name, From/To,
  # Product Category / Product Hierarchy (category/brand), Image URL, Created Date
  # (photo taken), Activity Type. A new upload SUPERSEDES the campaign's previous
  # evidence (one live result set per campaign).
  class DisplayEvidenceImporter < BaseImporter
    JOB_TYPE = :display_evidence_import

    def initialize(io_or_string, campaign:, user:, filename: nil, log: nil)
      super(io_or_string, user: user, filename: filename, log: log)
      @campaign = campaign
    end

    def call
      JobLog.track(JOB_TYPE, user: @user, filename: @filename, log: @log) do |log|
        rows = CSV.parse(@data, headers: true)
        log.total_rows = rows.size
        batch = SecureRandom.hex(6)
        store_cache = {}
        buf = []

        rows.each_with_index do |row, i|
          code  = DisplayCampaign.extract_store_code(row["Store Name"])
          promo = row["Promotion Name"].to_s.strip
          raise "missing store code (Store Name: #{row['Store Name'].inspect})" if code.blank?
          raise "missing promotion name" if promo.blank?

          sid = store_cache.fetch(code) { store_cache[code] = Store.find_by(store_code: code)&.id }
          buf << { display_campaign_id: @campaign.id, store_code: code, store_id: sid,
                   promotion_name: promo,
                   from_date: parse_date(row["From"]), to_date: parse_date(row["To"]),
                   category: row["Product Category: Product Hierarchy Name"].to_s.strip.presence,
                   brand: row["Product Hierarchy: Product Hierarchy Name"].to_s.strip.presence,
                   image_url: row["Image URL"].to_s.strip.presence,
                   photo_taken_at: parse_date(row["Created Date"]),
                   activity_type: row["Activity Type"].to_s.strip.presence,
                   batch_token: batch, created_at: Time.current, updated_at: Time.current }
          log.processed_rows += 1
        rescue StandardError => e
          log.error_count += 1
          log.rejected_records_data << { line: i + 2, error: e.message, row: row.to_h }
        end

        DisplayEvidence.transaction do
          # Supersede the previous CSV. Delete via the class scope (not the
          # association) so a passed-in campaign object keeps no stale cache.
          DisplayEvidence.where(display_campaign_id: @campaign.id).delete_all
          buf.each_slice(1000) { |s| DisplayEvidence.insert_all(s) } if buf.any?
        end
        log.save!
      end
    end

    private

    def parse_date(val)
      s = val.to_s.strip
      return nil if s.blank?

      ["%m/%d/%Y", "%Y-%m-%d", "%m/%d/%y"].each do |fmt|
        return Date.strptime(s, fmt)
      rescue ArgumentError
        next
      end
      Date.parse(s)
    rescue ArgumentError
      nil
    end
  end
end
