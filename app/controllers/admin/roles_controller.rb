module Admin
  class RolesController < ApplicationController
    before_action -> { authorize!(:role, :view) }, only: [:index]
    before_action -> { authorize!(:role, :create) }, only: [:new, :create]
    before_action -> { authorize!(:role, :update) }, only: [:edit, :update]
    before_action :set_role, only: [:edit, :update]

    # Permission matrix: modules (resources) x roles.
    def index
      @roles = Role.active.order(:name).to_a
      @resources = Permission.distinct.order(:resource).pluck(:resource)
      @grants = Hash.new { |h, k| h[k] = [] }
      RolePermission.includes(:permission).where(role: @roles).find_each do |rp|
        @grants[[rp.permission.resource, rp.role_id]] << rp.permission.action
      end
    end

    def new
      @role = Role.new(active: true)
      load_permission_grid
    end

    def create
      @role = Role.new(role_params)
      if @role.save
        sync_permissions(@role)
        redirect_to admin_roles_path, notice: "Role “#{@role.name}” created."
      else
        load_permission_grid
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      load_permission_grid
    end

    def update
      if @role.update(role_params)
        sync_permissions(@role)
        redirect_to admin_roles_path, notice: "Role “#{@role.name}” updated."
      else
        load_permission_grid
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_role
      @role = Role.find(params[:id])
    end

    def role_params
      params.require(:role).permit(:name, :description, :active)
    end

    # Grid of resource -> [permissions] (only real resource/action combos),
    # plus the set of permission ids the role currently has.
    def load_permission_grid
      @grid = Permission.order(:resource, :action).group_by(&:resource)
      @granted_ids = @role.permission_ids.to_set
    end

    def sync_permissions(role)
      ids = Array(params.dig(:role, :permission_ids)).map(&:to_i).select(&:positive?)
      role.permission_ids = Permission.where(id: ids).pluck(:id)
    end
  end
end
