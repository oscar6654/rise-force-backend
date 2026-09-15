class Role < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :permissions, through: :role_permissions
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :active, inclusion: { in: [true, false] }

  scope :active, -> { where(active: true) }

  def has_permission?(resource, action)
    permissions.exists?(resource: resource.to_s, action: action.to_s)
  end

  # Grant a permission to this role, creating the Permission row if needed.
  def add_permission(resource, action)
    permission = Permission.find_or_create_by!(resource: resource.to_s, action: action.to_s)
    permissions << permission unless permissions.include?(permission)
    permission
  end
end
