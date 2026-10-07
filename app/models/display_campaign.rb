class DisplayCampaign < ApplicationRecord
  belongs_to :created_by, class_name: "User", optional: true
  has_many :display_targets, dependent: :delete_all
  has_many :display_evidences, dependent: :delete_all

  enum :status, { active: 0, archived: 1 }, default: :active

  validates :name, presence: true
  validates :period_from, :period_to, presence: true
  validate :period_order

  # Campaigns whose window contains the date — the app only shows live ones.
  scope :active_on, ->(date = Date.current) {
    where(status: :active).where("period_from <= ? AND period_to >= ?", date, date)
  }

  # Normalise promo / category / brand for case/space-insensitive matching.
  def self.norm(str)
    str.to_s.strip.gsub(/\s+/, " ").upcase
  end

  # The CU_#### store code from "CU_16347 - 529 STREET MART, INC" (xlsx col A /
  # csv col E): the first whitespace-delimited token.
  def self.extract_store_code(account)
    account.to_s.strip.split(/\s+/).first.presence
  end

  private

  def period_order
    return if period_from.blank? || period_to.blank?

    errors.add(:period_to, "must be on or after the start date") if period_to < period_from
  end
end
