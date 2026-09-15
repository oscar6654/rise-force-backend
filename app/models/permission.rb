class Permission < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions

  # Action vocabulary for the SFA console (see plan / RBAC design).
  # View / Create-Edit / Approve / Publish map onto these.
  ACTIONS = %w[view create update destroy approve publish sync download].freeze

  validates :resource, presence: true
  validates :action, presence: true
  validates :resource, uniqueness: { scope: :action }

  scope :for_resource, ->(resource) { where(resource: resource) }
  scope :for_action, ->(action) { where(action: action) }

  def display_name
    "#{action.humanize} #{resource.humanize}"
  end

  def full_permission
    "#{resource}.#{action}"
  end
end
