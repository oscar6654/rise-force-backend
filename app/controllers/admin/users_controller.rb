module Admin
  class UsersController < ApplicationController
    before_action -> { authorize!(:user, :view) }, only: [:index, :show]
    before_action -> { authorize!(:user, :create) }, only: [:new, :create]
    before_action -> { authorize!(:user, :update) },
                  only: [:edit, :update, :add_role, :remove_role]
    before_action :set_user, only: [:show, :edit, :update, :add_role, :remove_role]

    def index
      @users = User.includes(:roles, :branch).order(:email).page(params[:page]).per(25)
      @roles = Role.active.order(:name)
    end

    def show; end

    def new
      @user = User.new
    end

    def create
      @user = User.new(user_params)
      if @user.save
        @user.assign_role(params[:role]) if params[:role].present?
        redirect_to admin_users_path, notice: "User #{@user.email} created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      # Allow updating without changing password when blank.
      attrs = user_params
      attrs = attrs.except(:password, :password_confirmation) if attrs[:password].blank?
      if @user.update(attrs)
        redirect_to admin_user_path(@user), notice: "User updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def add_role
      role = Role.find(params[:role_id])
      if @user.roles.include?(role)
        redirect_to admin_users_path, alert: "#{@user.email} already has #{role.name}."
      else
        @user.roles << role
        redirect_to admin_users_path, notice: "Assigned #{role.name} to #{@user.email}."
      end
    end

    def remove_role
      role = Role.find(params[:role_id])
      @user.roles.destroy(role)
      redirect_to admin_users_path, notice: "Removed #{role.name} from #{@user.email}."
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:email, :first_name, :last_name, :branch_id,
                                   :status, :password, :password_confirmation)
    end
  end
end
