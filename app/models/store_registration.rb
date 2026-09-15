class StoreRegistration < ApplicationRecord
  belongs_to :seller
  belongs_to :branch
  belongs_to :channel, optional: true
  belongs_to :duplicate_of_store, class_name: "Store", optional: true
  belongs_to :provisional_store, class_name: "Store", optional: true
  belongs_to :created_store, class_name: "Store", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true
  has_one_attached :storefront_photo

  enum :status, { pending: 0, approved: 1, rejected: 2 }, default: :pending
  enum :proposed_category, { platinum: 0, gold: 1, silver: 2, bronze: 3 }, prefix: :category

  validates :client_uuid, presence: true, uniqueness: true
  validates :name, presence: true

  scope :for_branches, ->(ids) { where(branch_id: ids) }

  def flagged_duplicate?
    duplicate_flags.present? || duplicate_of_store_id.present?
  end

  # The category a new enrollment starts on so the seller can sell immediately.
  # Sellers pick the CHANNEL in the app; the backend assigns this default
  # category (configurable), and a reviewer can reassign it at approval — the
  # store edit page and pricing then follow on the next sync.
  def self.default_category_code
    SystemSetting.get("default_enrollment_category", "silver").to_s.presence || "silver"
  end

  # An explicitly proposed category still wins (legacy/manual), else the default.
  def provision_category_code
    proposed_category.presence || self.class.default_category_code
  end

  # The weekday the seller enrolled this store, used as the default visit day at
  # approval so the store lands on the route on the same day it was registered.
  # Sunday enrollments (no Sunday route) fall back to Monday.
  def enrolled_visit_day
    wday = (created_at || Time.current).in_time_zone.wday # 0=Sun..6=Sat
    return "mon" if wday.zero?

    %w[mon tue wed thu fri sat][wday - 1]
  end

  # Create the provisional store so the field app can order immediately, before
  # backend approval. Idempotent. Returns the provisional Store.
  def provision_store!
    return provisional_store if provisional_store

    store = Store.create!(
      branch: branch, channel: channel, name: name, owner_name: owner_name,
      contact_number: contact_number, address: address,
      latitude: latitude, longitude: longitude,
      category_code: provision_category_code, status: :provisional,
      provisional_code: generate_provisional_code, store_registration_id: id
    )
    update!(provisional_store: store)
    store
  end

  # Approve: promote the provisional store to active with a permanent code, or
  # link/redirect to an existing store when the reviewer marks it a duplicate.
  # The reviewer may reassign channel/category here (blank = keep as provisioned);
  # the change flows to pricing on the store's next price sync. Route + visit day
  # slot the store onto the seller's route so it appears on the call list — the
  # visit day defaults to the day the seller enrolled it.
  def approve!(reviewer:, permanent_code:, duplicate_of: nil, channel_id: nil, category_code: nil,
               route_id: nil, visit_day: nil, visit_frequency: nil, week_pattern: nil)
    transaction do
      if duplicate_of
        # Re-point any provisional store's origin to the existing store.
        provisional_store&.update!(status: :rejected)
        update!(status: :approved, reviewed_by: reviewer, reviewed_at: Time.current,
                created_store: duplicate_of, duplicate_of_store: duplicate_of)
        duplicate_of
      else
        store = provisional_store || Store.new(branch: branch, channel: channel, name: name,
                  owner_name: owner_name, contact_number: contact_number, address: address,
                  latitude: latitude, longitude: longitude, category_code: provision_category_code,
                  store_registration_id: id)
        store.assign_attributes(store_code: permanent_code, provisional_code: nil, status: :active)
        store.channel_id = channel_id if channel_id.present?
        store.category_code = category_code if category_code.present?
        store.route_id = route_id if route_id.present?
        store.visit_frequency = visit_frequency if visit_frequency.present?
        store.week_pattern = week_pattern if week_pattern.present?
        store.visit_day = (visit_day.presence || enrolled_visit_day)
        store.visit_sequence ||= next_route_sequence(store.route_id)
        store.save!
        update!(status: :approved, reviewed_by: reviewer, reviewed_at: Time.current, created_store: store)
        store
      end
    end
  end

  def reject!(reviewer:, reason:)
    transaction do
      provisional_store&.update!(status: :rejected)
      update!(status: :rejected, reviewed_by: reviewer, reviewed_at: Time.current, rejection_reason: reason)
    end
  end

  private

  # Append the new store to the end of the route's visit order.
  def next_route_sequence(route_id)
    return nil if route_id.blank?

    (Store.where(route_id: route_id).maximum(:visit_sequence) || 0) + 1
  end

  def generate_provisional_code
    prefix = SystemSetting.get("provisional_code_prefix", "PROV")
    "#{prefix}-#{branch.code}-#{SecureRandom.hex(3).upcase}"
  end
end
