module Wms
  # Checker verifies what the picker staged. Records qty_checked per line (a
  # `check` movement — no stock change, just the verified figure), then closes
  # the job to `checked`. For a split job the parent consolidates once all its
  # child jobs are checked.
  class CheckingService
    def initialize(staff: nil)
      @staff = staff
    end

    def verify!(line, qty_checked:)
      qty_checked = qty_checked.to_d
      line.update!(qty_checked: qty_checked, status: :checked)
      Ledger.record!(warehouse: line.fulfillment_order.warehouse, type: :check, quantity: qty_checked,
                     field: :on_hand, product: line.product, fulfillment_order: line.fulfillment_order,
                     staff: @staff, reason: "check")
      line
    end

    # Close the job once every line is checked; cascade to the parent shell.
    def complete!(fulfillment_order)
      return fulfillment_order unless fulfillment_order.fulfillment_lines.where.not(status: :checked).empty?

      fulfillment_order.update!(status: :checked, checked_by: @staff, checked_at: Time.current)
      consolidate_parent!(fulfillment_order.parent_fulfillment_order)
      fulfillment_order
    end

    private

    def consolidate_parent!(parent)
      return unless parent
      return if parent.child_fulfillment_orders.where.not(status: :checked).exists?
      # Guard: never consolidate while the parent still has its own unchecked
      # lines (should be none once a job is fully split, but don't drop demand).
      return if parent.fulfillment_lines.where.not(status: :checked).exists?

      parent.update!(status: :checked, checked_at: Time.current)
    end
  end
end
