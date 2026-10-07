require "roo"

module Import
  # Parses the display-target BASE xlsx (Sheet1): col A Account (→ CU_#### store
  # code), B Promotion Name, C Category, D Brand (blank = any brand). Populates a
  # campaign's target lines. Takes a FILE PATH (roo needs one). Re-running clears
  # and reloads the campaign's targets.
  class DisplayTargetsImporter
    JOB_TYPE = :display_target_import

    def initialize(path, campaign:, user:, filename: nil, log: nil)
      @path = path
      @campaign = campaign
      @user = user
      @filename = filename
      @log = log
    end

    def call
      JobLog.track(JOB_TYPE, user: @user, filename: @filename, log: @log) do |log|
        sheet = Roo::Spreadsheet.open(@path, extension: :xlsx).sheet(0)
        last = sheet.last_row.to_i
        log.total_rows = [last - 1, 0].max
        store_cache = {}
        buf = []

        (2..last).each do |i|
          account  = sheet.cell(i, 1)
          promo    = sheet.cell(i, 2)
          category = sheet.cell(i, 3)
          brand    = sheet.cell(i, 4)
          next if account.blank? && promo.blank? # trailing/empty row

          code = DisplayCampaign.extract_store_code(account)
          raise "missing store code (col A: #{account.inspect})" if code.blank?
          raise "missing promotion name" if promo.blank?

          sid = store_cache.fetch(code) { store_cache[code] = Store.find_by(store_code: code)&.id }
          buf << { display_campaign_id: @campaign.id, store_code: code, store_id: sid,
                   promotion_name: promo.to_s.strip,
                   category: category.to_s.strip.presence, brand: brand.to_s.strip.presence,
                   created_at: Time.current, updated_at: Time.current }
          log.processed_rows += 1
        rescue StandardError => e
          log.error_count += 1
          log.rejected_records_data << { line: i, error: e.message }
        end

        DisplayTarget.transaction do
          DisplayTarget.where(display_campaign_id: @campaign.id).delete_all
          buf.each_slice(1000) { |s| DisplayTarget.insert_all(s) } if buf.any?
        end
        log.save!
      end
    end
  end
end
