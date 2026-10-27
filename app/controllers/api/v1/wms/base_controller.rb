module Api
  module V1
    module Wms
      # Shared base for the WMS mobile endpoints: requires a logged-in warehouse
      # staff and exposes their warehouse. Each controller gates on a role.
      class BaseController < Api::V1::BaseController
        before_action :require_staff!

        private

        def require_staff!
          render_unauthorized unless current_role == "staff" && current_warehouse_staff
        end

        def warehouse
          @warehouse ||= current_warehouse_staff.warehouse
        end
      end
    end
  end
end
