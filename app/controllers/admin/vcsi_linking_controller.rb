module Admin
  # Guide + health check for the vcsi_rise integration. Shows what must be
  # linked (which local record maps to which vcsi_rise key), whether the
  # settings are configured, local link coverage, and — when the API is
  # reachable — which links are VALID vs INVALID (a ref that doesn't exist in
  # vcsi_rise) so bad links are caught before they cause silent sync gaps.
  class VcsiLinkingController < ApplicationController
    before_action -> { authorize!(:system_setting, :view) }

    def show
      @configured = SystemSetting.get("vcsi_rise_base_url").present? &&
                    SystemSetting.get("vcsi_rise_api_token").present?

      @coverage = {
        seller:  link_stat(Seller.all, :vcsi_sales_rep_ref),
        store:   link_stat(Store.all, :vcsi_customer_ref),
        product: link_stat(Product.all, :vcsi_product_ref),
        branch:  link_stat(Branch.all, :vcsi_branch_ref)
      }
      @unlinked_sellers = Seller.where(vcsi_sales_rep_ref: [nil, ""]).order(:name).limit(50)

      @last_target_sync = JobLog.where(job_type: :target_sync).recent.first
      @last_sellout_sync = JobLog.where(job_type: :sellout_sync).recent.first

      validate_against_vcsi if @configured && params[:validate].present?
    end

    private

    def link_stat(scope, column)
      total = scope.count
      linked = scope.where.not(column => [nil, ""]).count
      { total: total, linked: linked, unlinked: total - linked }
    end

    # Cross-check local seller + store refs against the live vcsi_rise feeds.
    def validate_against_vcsi
      client = VcsiRise::Client.new

      # --- Sellers: pull the whole master (small) and diff both ways. ---------
      remote = client.sellers
      remote_reps = remote.map { |r| r["sales_rep"].to_s }.to_set
      local = Seller.where.not(vcsi_sales_rep_ref: [nil, ""])
      @valid_links = local.select { |s| remote_reps.include?(s.vcsi_sales_rep_ref.to_s) }
      @invalid_links = local.reject { |s| remote_reps.include?(s.vcsi_sales_rep_ref.to_s) }
      @unmatched_remote = remote.reject { |r| local.any? { |s| s.vcsi_sales_rep_ref.to_s == r["sales_rep"].to_s } }

      # --- Stores: the customer master is huge, so validate ONLY the refs the
      # SFA side has set (send them, ask which exist). No "unmatched remote". ---
      linked_stores = Store.where.not(vcsi_customer_ref: [nil, ""])
      refs = linked_stores.map { |s| s.vcsi_customer_ref.to_s }.uniq
      existing = refs.any? ? client.stores(ids: refs).map { |r| r["customer_id"].to_s }.to_set : Set.new
      @store_valid = linked_stores.select { |s| existing.include?(s.vcsi_customer_ref.to_s) }
      @store_invalid = linked_stores.reject { |s| existing.include?(s.vcsi_customer_ref.to_s) }

      @validation_ran = true
    rescue StandardError => e
      @validation_error = e.message
    end
  end
end
