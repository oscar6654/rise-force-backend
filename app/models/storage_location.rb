class StorageLocation < ApplicationRecord
  belongs_to :warehouse
  has_many :inventory_lots, dependent: :restrict_with_error

  # pick_rack = normal selective racking; buffer = overflow (not pickable);
  # high_value = secured shelf (multi-lot); damage = quarantine/damaged holding;
  # receiving_dock = where receipts land before putaway.
  enum :loc_type, {
    pick_rack: 0, bulk: 1, buffer: 2, high_value: 3, damage: 4, staging: 5, receiving_dock: 6
  }, default: :pick_rack
  enum :status, { active: 0, inactive: 1 }, default: :active

  validates :loc_code, presence: true, uniqueness: { scope: :warehouse_id, case_sensitive: false }
  validates :slot_capacity, numericality: { greater_than_or_equal_to: 1 }

  scope :pickable, -> { where(pickable: true, status: :active) }
  scope :by_sequence, -> { order(:pick_sequence, :loc_code) }

  # A location is piece-pick (loose/broken-case) when it sits in the warehouse's
  # designated piece_pick_zone; otherwise it's a full-case pick location.
  def piece_pick?
    zone.present? && warehouse.piece_pick_zone.present? &&
      zone.casecmp?(warehouse.piece_pick_zone)
  end

  def case_pick?
    !piece_pick?
  end

  # Occupied slots = distinct lots currently holding stock here. A mono-lot slot
  # (allow_mixed_lots = false) is a putaway candidate only when it holds nothing;
  # a mixed-lot location (loose/high_value/buffer) accepts up to slot_capacity lots.
  def occupied_slots
    inventory_lots.where("qty_on_hand > 0").count
  end

  def has_free_slot?
    occupied_slots < slot_capacity
  end

  # Does this location accept the given product? Empty acceptance arrays = any.
  def accepts?(product)
    abc_ok   = allowed_abc_classes.blank? || allowed_abc_classes.include?(product.abc_class.to_s)
    brand_ok = allowed_brand_ids.blank? || (product.brand_id && allowed_brand_ids.include?(product.brand_id))
    abc_ok && brand_ok
  end
end
