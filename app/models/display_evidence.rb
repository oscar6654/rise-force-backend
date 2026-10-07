class DisplayEvidence < ApplicationRecord
  belongs_to :display_campaign
  belongs_to :store, optional: true

  validates :store_code, :promotion_name, presence: true

  # Evidence counts only if its own [from,to] window overlaps the campaign's.
  scope :overlapping, ->(from, to) {
    where("(from_date IS NULL OR from_date <= ?) AND (to_date IS NULL OR to_date >= ?)", to, from)
  }
end
