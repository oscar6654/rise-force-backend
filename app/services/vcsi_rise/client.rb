# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module VcsiRise
  # Read-only client for the vcsi_rise ERP API (source of truth for actual
  # sellout/stock/targets). Credentials come from SystemSetting (category
  # `vcsi`). Sync endpoints are added in the vcsi_rise-sync milestone; for now
  # it supports #ping so the admin "Test connection" button works.
  class Client
    class Error < StandardError; end

    def initialize(base_url: nil, token: nil)
      @base_url = (base_url || SystemSetting.get("vcsi_rise_base_url")).to_s.chomp("/")
      @token = token || SystemSetting.get("vcsi_rise_api_token")
    end

    # Returns { ok: true/false, detail: "..." } — never raises.
    def ping
      return { ok: false, detail: "vcsi_rise_base_url not configured" } if @base_url.blank?

      response = get("/up")
      if response.is_a?(Net::HTTPSuccess)
        { ok: true, detail: "HTTP #{response.code}" }
      else
        { ok: false, detail: "HTTP #{response.code}" }
      end
    rescue StandardError => e
      { ok: false, detail: e.message }
    end

    # Generic authenticated GET returning parsed JSON (used by sync jobs).
    def get_json(path, params = {})
      response = get(path, params)
      raise Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    # --- Read-only sync endpoints (vcsi_rise is the source of truth) ---------
    # Backed by vcsi_rise Api::V1::Sfa endpoints (bearer = McpAccessToken).
    # Each returns an array of row hashes. Paths overridable via SystemSetting.

    # Seller master + monthly target, keyed by sales_rep. Rows:
    #   { sales_rep, seller_name, supervisor_name, gsm_name, om_name,
    #     sales_target, user_id, user_email, supervisor_user_id }
    def sellers(sales_rep: nil)
      path = SystemSetting.get("vcsi_sellers_path", "/api/v1/sfa/sellers")
      params = sales_rep.present? ? { sales_rep: sales_rep } : {}
      Array(get_json(path, params)["data"])
    end
    alias_method :targets, :sellers # targets ride on the seller feed

    # Actual MTD sellout per sales_rep (GIV*1.12). Pass sales_rep to scope to one
    # seller (on-demand app pull). Rows:
    #   { sales_rep, sellout, giv, transactions, unique_customers }
    def sellout(month: Date.current.beginning_of_month, sales_rep: nil)
      path = SystemSetting.get("vcsi_sellout_path", "/api/v1/sfa/sellout")
      params = { month: month.strftime("%Y-%m") }
      params[:sales_rep] = sales_rep if sales_rep.present?
      Array(get_json(path, params)["data"])
    end

    # Customer (store) master, keyed by customer_id — used to validate store
    # links. Rows: { customer_id, customer_name, branch, chain, segment,
    # sales_rep, active }. Pass `ids` (the local refs) to validate just those —
    # the full master is very large, so link checks always send specific ids.
    def stores(ids: nil)
      path = SystemSetting.get("vcsi_stores_path", "/api/v1/sfa/stores")
      params = {}
      params[:ids] = Array(ids).join(",") if ids.present?
      Array(get_json(path, params)["data"])
    end

    # Actual MTD sellout per customer/store (GIV*1.12). Rows:
    #   { customer_id, customer_name, sales_rep, sellout, giv, transactions }
    def store_sellout(month: Date.current.beginning_of_month, sales_rep: nil)
      path = SystemSetting.get("vcsi_store_sellout_path", "/api/v1/sfa/store_sellout")
      params = { month: month.strftime("%Y-%m") }
      params[:sales_rep] = sales_rep if sales_rep.present?
      Array(get_json(path, params)["data"])
    end

    # Per-STORE per-SKU confirmed (invoiced) sellout for a month. Feeds must-carry
    # "carried" from actual invoices. Rows: { customer_id, it_barcode, pieces, amount }.
    # Optional endpoint — an undeployed path / any error yields [], so must-carry
    # falls back to SFA presell orders until vcsi_rise exposes it.
    def store_sku_sellout(month: Date.current.beginning_of_month, sales_rep: nil)
      path = SystemSetting.get("vcsi_store_sku_sellout_path", "/api/v1/sfa/store_sku_sellout")
      params = { month: month.strftime("%Y-%m") }
      params[:sales_rep] = sales_rep if sales_rep.present?
      Array(get_json(path, params)["data"])
    rescue StandardError
      []
    end

    # Per-seller per-SKU confirmed sellout in PIECES, scoped to focus barcodes.
    # Rows: { sales_rep, it_barcode, pieces, amount }
    def sku_sellout(month: Date.current.beginning_of_month, sales_rep:, barcodes:)
      path = SystemSetting.get("vcsi_sku_sellout_path", "/api/v1/sfa/sku_sellout")
      params = { month: month.strftime("%Y-%m"), sales_rep: sales_rep, barcodes: Array(barcodes).join(",") }
      Array(get_json(path, params)["data"])
    end

    # Trailing monthly sellout per customer/store — raw material for deriving
    # store targets. `through` defaults server-side to the last completed month.
    # Rows: { customer_id, month: "YYYY-MM", sellout }
    # Per-store LAST confirmed (invoiced) order lines from vcsi_rise, for
    # prefilling order-taking & stock check. Rows: { it_barcode, qty, uom,
    # ordered_on }. Optional endpoint — an undeployed path / any error yields [],
    # so prefill falls back to SFA presell history.
    def store_last_order(customer_id:)
      return [] if customer_id.blank?

      path = SystemSetting.get("vcsi_store_last_order_path", "/api/v1/sfa/store_last_order")
      Array(get_json(path, customer_id: customer_id)["data"])
    rescue StandardError
      []
    end

    def store_history(months: 3, through: nil)
      path = SystemSetting.get("vcsi_store_history_path", "/api/v1/sfa/store_history")
      params = { months: months }
      params[:through] = through.strftime("%Y-%m") if through
      Array(get_json(path, params)["data"])
    end

    private

    def get(path, params = {})
      uri = URI.join(@base_url + "/", path.delete_prefix("/"))
      uri.query = URI.encode_www_form(params) if params.present?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 5
      http.read_timeout = 15

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@token}" if @token.present?
      request["Accept"] = "application/json"
      http.request(request)
    end
  end
end
