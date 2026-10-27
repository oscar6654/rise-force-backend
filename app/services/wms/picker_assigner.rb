module Wms
  # Assign an allocated fulfillment order to the picker(s) who own its work.
  # brand_per_picker: owner = a pick-role staff whose brand_ids include the line's
  #   product brand. zone_per_picker: owner = a pick-role staff whose zones include
  #   the allocation's location zone. A job whose lines span different owners is
  #   SPLIT into one child FO per owner (parent consolidates at checking). Ties
  #   break to the least-loaded picker; no owner → left unassigned.
  class PickerAssigner
    def initialize(fulfillment_order)
      @fo = fulfillment_order
      @warehouse = fulfillment_order.warehouse
      @strategy = @warehouse.allocation_strategy
    end

    def assign!
      return @fo unless @fo.allocated? || @fo.short?

      owners = owner_by_line # { fulfillment_line_id => WarehouseStaff|nil }
      # If ANY line has no eligible online owner, leave the whole job unassigned
      # (status stays allocated/short) so AssignUnassignedJob retries it when a
      # picker logs in. Splitting with some lines unowned would strand them on the
      # parent shell and let it dispatch without those lines being picked.
      return @fo if owners.values.any?(&:nil?)

      distinct = owners.values.uniq
      ApplicationRecord.transaction do
        if distinct.size <= 1
          assign_whole(distinct.first)
        else
          split_by_owner(owners) # every line is owned → each moves to a child
        end
      end
      @fo
    end

    private

    # Only pickers who are ONLINE (logged into the app + recently active) are
    # eligible — an absent picker is never auto-assigned. If nobody is online the
    # job stays unassigned (a supervisor assigns it, or it picks up a picker on a
    # later re-allocate once someone logs in).
    # Online staff who can pick either full cases or loose pieces.
    def pickers
      @pickers ||= @warehouse.warehouse_staffs.online.select { |s| s.has_role?("pick") || s.has_role?("pick_pieces") }
    end

    def owner_by_line
      @fo.fulfillment_lines.includes(:product).each_with_object({}) do |line, h|
        h[line.id] = owner_for(line)
      end
    end

    # A loose (broken-case) line needs a pieces picker; a case line needs a case
    # picker. A staff holding both roles is eligible for both.
    def owner_for(line)
      role = line.pack_loose? ? "pick_pieces" : "pick"
      role_pool = pickers.select { |p| p.has_role?(role) }
      eligible =
        if @strategy == "zone_per_picker"
          zones = line_zones(line)
          role_pool.select { |p| (p.zones & zones).any? }
        else
          role_pool.select { |p| p.brand_ids.include?(line.product.brand_id) }
        end
      least_loaded(eligible)
    end

    def line_zones(line)
      PickAllocation.where(fulfillment_line_id: line.id)
                    .joins(:storage_location).pluck("storage_locations.zone").compact.uniq
    end

    def least_loaded(staff)
      return nil if staff.empty?

      staff.min_by { |s| FulfillmentOrder.open_jobs.where(assigned_to_id: s.id).count }
    end

    def assign_whole(owner)
      @fo.update!(assigned_to: owner, status: owner ? :assigned : @fo.status)
    end

    # Move each owner's lines (+ their allocations) onto a child FO and assign it.
    def split_by_owner(owners)
      grouped = owners.select { |_id, owner| owner }.group_by { |_id, owner| owner }
      grouped.each do |owner, pairs|
        line_ids = pairs.map(&:first)
        child = FulfillmentOrder.create!(
          warehouse: @warehouse, order: @fo.order, store: @fo.store,
          parent_fulfillment_order: @fo, reference_no: "#{@fo.reference_no}-#{owner.staff_code}",
          source: @fo.source, status: :assigned, assigned_to: owner,
          delivery_date: @fo.delivery_date, remarks: @fo.remarks, demand_date: @fo.demand_date,
          allocated_at: @fo.allocated_at
        )
        FulfillmentLine.where(id: line_ids).update_all(fulfillment_order_id: child.id)
        PickAllocation.where(fulfillment_line_id: line_ids).update_all(fulfillment_order_id: child.id)
      end
      # Parent keeps any unowned lines; it becomes the consolidation shell.
      @fo.update!(assigned_to: nil, status: :assigned)
    end
  end
end
