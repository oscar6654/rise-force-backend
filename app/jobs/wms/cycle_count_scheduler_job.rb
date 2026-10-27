module Wms
  # Open random/scheduled cycle counts across WMS warehouses. Count cadence (how
  # many locations per warehouse per run) is a SystemSetting; selection is
  # weighted by the location's accepted ABC class so A-dedicated bins are counted
  # more often than C. Runs from recurring.yml; scheduled by backend, not AI.
  class CycleCountSchedulerJob < ApplicationJob
    queue_as :default

    # Relative selection weight by accepted ABC class (A counted most often).
    ABC_WEIGHT = { "A" => 5, "B" => 2, "C" => 1 }.freeze

    def perform
      per_wh = SystemSetting.get("wms_cycle_count_per_run", "5").to_i
      return if per_wh <= 0

      Warehouse.wms.find_each do |wh|
        # Weighted-random, distinct: shuffle a pool that repeats higher-ABC
        # locations, then take the first N unique ones.
        pick_locations(wh).shuffle.uniq.first(per_wh).each do |loc|
          Wms::CycleCountService.open!(loc, trigger: :scheduled, reason: "scheduled cycle count")
        end
      end
    end

    private

    # Occupied, countable locations (skip the dock). Weighting is approximated by
    # repeating higher-ABC locations in the pool before sampling.
    def pick_locations(warehouse)
      locs = warehouse.storage_locations.where.not(loc_type: :receiving_dock)
                      .where(status: StorageLocation.statuses[:active]).to_a
                      .select { |l| l.inventory_lots.where("qty_on_hand > 0").exists? }
      locs.flat_map { |l| [l] * weight_for(l) }
    end

    def weight_for(loc)
      loc.allowed_abc_classes.map { |c| ABC_WEIGHT[c.to_s.upcase] || 1 }.max || 1
    end
  end
end
