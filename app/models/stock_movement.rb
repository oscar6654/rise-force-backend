class StockMovement < ApplicationRecord
  belongs_to :warehouse
  belongs_to :inventory_lot, optional: true
  belongs_to :storage_location, optional: true
  belongs_to :to_storage_location, class_name: "StorageLocation", optional: true
  belongs_to :product, optional: true
  belongs_to :receipt, optional: true
  belongs_to :fulfillment_order, optional: true
  belongs_to :pick_allocation, optional: true
  belongs_to :cycle_count, optional: true
  belongs_to :warehouse_staff, optional: true
  belongs_to :user, optional: true

  # Append-only ledger. Every counter change writes one row; the sign of
  # `quantity` + `field` says what moved. This is the substrate a later AI layer
  # reads — never UPDATE or DELETE a movement, only append a correcting one.
  # Prefixed (`mt_*` / `field_*`) because some values (e.g. `allocate`) would
  # otherwise generate class methods that clash with Ruby/ActiveRecord.
  enum :movement_type, {
    receipt: 0, putaway: 1, relocate: 2, allocate: 3, deallocate: 4, lock: 5,
    unlock: 6, pick: 7, check: 8, short: 9, adjust: 10, return_in: 11, damage: 12,
    quarantine: 13, release: 14, writeoff: 15
  }, prefix: :mt
  enum :field, { on_hand: 0, allocated: 1, locked: 2 }, default: :on_hand, prefix: :field

  before_validation { self.occurred_at ||= Time.current }

  scope :recent, -> { order(occurred_at: :desc) }

  # Shared audit-trail filter for the console ledger view and the CSV export, so
  # the on-screen list and the download always agree. All params optional:
  # warehouse_id, movement_type, staff_code, and a from/to date window (inclusive,
  # whole days) on occurred_at.
  def self.filtered(params)
    scope = all
    scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
    scope = scope.where(movement_type: params[:movement_type]) if params[:movement_type].present?
    if params[:staff_code].present?
      scope = scope.joins(:warehouse_staff).where(warehouse_staffs: { staff_code: params[:staff_code] })
    end
    if (from = parse_audit_date(params[:from]))
      scope = scope.where("stock_movements.occurred_at >= ?", from.beginning_of_day)
    end
    if (to = parse_audit_date(params[:to]))
      scope = scope.where("stock_movements.occurred_at <= ?", to.end_of_day)
    end
    scope
  end

  # Lenient ISO date parse — a blank or malformed date just drops that bound.
  def self.parse_audit_date(str)
    return nil if str.blank?

    Date.iso8601(str.to_s)
  rescue ArgumentError
    nil
  end
end
