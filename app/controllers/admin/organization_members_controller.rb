# app/controllers/admin/organization_members_controller.rb
class Admin::OrganizationMembersController < Admin::BaseController
  before_action :set_organization
  before_action :set_member, only: %i[update_role remove]

  def index
    authorize @organization, :manage_members?
    @pagy, @members = pagy(@organization.organization_memberships.includes(:user).order(created_at: :desc))

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def update_role
    authorize @organization, :manage_members?

    if @member.update(role: params[:role])
      respond_to do |format|
        format.html { redirect_to admin_organization_members_path(@organization), notice: "Member role updated." }
        format.turbo_stream { head :ok }
      end
    else
      respond_to do |format|
        format.html { redirect_to admin_organization_members_path(@organization), alert: "Unable to update role." }
        format.turbo_stream { head :unprocessable_entity }
      end
    end
  end

  def remove
    authorize @organization, :manage_members?

    @member.destroy
    respond_to do |format|
      format.html { redirect_to admin_organization_members_path(@organization), notice: "Member removed." }
      format.turbo_stream { head :ok }
    end
  end

  private

  def set_organization
    @organization = Organization.find(params[:organization_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_organizations_path, alert: "Organization not found."
  end

  def set_member
    @member = @organization.organization_memberships.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to admin_organization_members_path(@organization), alert: "Member not found."
  end
end
