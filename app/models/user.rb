class User < ApplicationRecord
  # Backend console login. Users are created/managed by admins (no public
  # sign-up), so :registerable/:confirmable are intentionally omitted.
  devise :database_authenticatable, :recoverable, :rememberable,
         :trackable, :validatable

  belongs_to :branch, optional: true

  # RBAC (mirrors vcsi_rise): User -> Roles -> Permissions.
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :permissions, through: :roles

  has_one_attached :profile_picture

  enum :status, { active: 0, inactive: 1 }, default: :active

  validates :first_name, presence: true
  validates :last_name, presence: true

  after_create :assign_default_role

  # --- Permission checks -------------------------------------------------
  def has_permission?(resource, action)
    permissions.exists?(resource: resource.to_s, action: action.to_s)
  end
  alias_method :can?, :has_permission?

  def cannot?(resource, action)
    !can?(resource, action)
  end

  def has_role?(role_name)
    roles.exists?(name: role_name.to_s)
  end

  def has_any_role?(*role_names)
    role_names.any? { |name| has_role?(name) }
  end

  def role_names
    roles.pluck(:name)
  end

  def assign_role(role_name)
    role = Role.find_by(name: role_name.to_s)
    return false unless role&.active?

    roles << role unless roles.include?(role)
    true
  end

  def superadmin?
    has_role?("superadmin")
  end

  # --- Branch scoping ----------------------------------------------------
  # branch_id nil => global access to every branch (superadmin / national).
  def branch_scoped?
    branch_id.present?
  end

  def all_branches?
    !branch_scoped?
  end

  def accessible_branch_ids
    branch_scoped? ? [branch_id] : Branch.pluck(:id)
  end

  def full_name
    [first_name, last_name].compact.join(" ").presence || email
  end

  def initials
    "#{first_name&.first}#{last_name&.first}".upcase.presence || email[0, 2].upcase
  end

  def primary_role_display
    roles.first&.name&.titleize || "No role"
  end

  private

  def assign_default_role
    assign_role("viewer") if roles.empty?
  end
end
