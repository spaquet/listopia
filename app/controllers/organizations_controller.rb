class OrganizationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization, only: [:show, :edit, :update, :destroy, :members, :suspend, :reactivate]
  before_action :require_organization!, only: [:show, :edit, :update, :members]

  def index
    @organizations = policy_scope(Organization)
    @pagy, @organizations = pagy(@organizations.order(created_at: :desc))
  end

  def show
    authorize @organization, :show?
  end

  def new
    @organization = Organization.new
    authorize @organization, :create?
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def create
    @organization = current_user.organizations.build(organization_params)
    @organization.created_by_id = current_user.id
    authorize @organization, :create?

    if @organization.save
      # Add creator as owner
      @organization.organization_memberships.create!(
        user: current_user,
        role: :owner,
        status: :active
      )

      # Set as current organization
      self.current_organization = @organization

      respond_to do |format|
        format.html { redirect_to organization_path(@organization), notice: "Organization created successfully." }
        format.turbo_stream { render :create }
      end
    else
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.turbo_stream { render :new }
      end
    end
  end

  def edit
    authorize @organization, :update?
  end

  def update
    authorize @organization, :update?

    if @organization.update(organization_params)
      redirect_to organization_path(@organization), notice: "Organization updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @organization, :destroy?

    if @organization.destroy
      # Clear current_organization if we just deleted it
      self.current_organization = nil if current_organization == @organization
      redirect_to organizations_path, notice: "Organization deleted successfully."
    else
      redirect_to organization_path(@organization), alert: "Unable to delete organization."
    end
  end

  def members
    authorize @organization, :manage_members?
    @pagy, @members = pagy(@organization.organization_memberships.includes(:user).order(created_at: :desc))
  end

  def suspend
    authorize @organization, :suspend?

    if @organization.update(status: :suspended)
      redirect_to organization_path(@organization), notice: "Organization suspended successfully."
    else
      redirect_to organization_path(@organization), alert: "Unable to suspend organization."
    end
  end

  def reactivate
    authorize @organization, :reactivate?

    if @organization.update(status: :active)
      redirect_to organization_path(@organization), notice: "Organization reactivated successfully."
    else
      redirect_to organization_path(@organization), alert: "Unable to reactivate organization."
    end
  end

  def switch
    org = Organization.find(params[:organization_id])
    authorize org, :show?

    self.current_organization = org
    redirect_to organization_path(org), notice: "Switched to #{org.name}."
  end

  private

  def set_organization
    @organization = Organization.find(params[:id])
  end

  def organization_params
    params.require(:organization).permit(:name, :size)
  end
end
