module Admin
  class AuditController < BaseController
    helper Admin::AuditHelper

    def index
      @organization = Current.organization
      @days = params[:days]&.to_i || 30

      if @organization
        @summary = audit_summary(@organization, @days.days.ago, Time.current)
        @sensitive_changes = sensitive_changes_log(@organization, @days)
        @recent_events = organization_events(@organization, limit: 50)
      else
        redirect_to admin_root_path, alert: "Please select an organization first"
      end
    end

    def compliance_report
      @organization = Current.organization
      redirect_to admin_root_path, alert: "Please select an organization first" unless @organization

      @days = params[:days]&.to_i || 90
      @start_date = (Time.current - @days.days).beginning_of_day
      @end_date = Time.current.end_of_day

      events = Event.where(organization_id: @organization.id)
                    .where("created_at >= ? AND created_at <= ?", @start_date, @end_date)

      @report = compliance_report(@organization, start_date: @start_date, end_date: @end_date)
      @html_report = @report.to_html

      respond_to do |format|
        format.html
        format.json { render json: @report.to_json }
        format.csv do
          send_data @report.to_csv, filename: "compliance_report_#{@selected_org.id}_#{Time.current.to_date}.csv"
        end
      end
    end

    def activity_log
      @organization = Current.organization
      redirect_to admin_root_path, alert: "Please select an organization first" unless @organization

      @user = @organization.users.find_by(id: params[:user_id])
      @days = params[:days]&.to_i || 30

      if @user
        @events = user_activity_log(@organization, @user, @days)
        @summary = {
          total_events: @events.count,
          events_by_type: @events.group_by(&:event_type).transform_values(&:count),
          date_range: {
            start: @events.map(&:created_at).min,
            end: @events.map(&:created_at).max
          }
        }
      else
        @users = @organization.users
        @summary = {}
      end

      respond_to do |format|
        format.html
        format.csv do
          send_data export_activity_log_csv(@events), filename: "activity_log_#{@user.id}_#{Time.current.to_date}.csv"
        end
      end
    end

    def audit_trail
      @organization = Current.organization
      redirect_to admin_root_path, alert: "Please select an organization first" unless @organization

      @resource_type = params[:resource_type]
      @resource_id = params[:resource_id]

      if @resource_type && @resource_id
        @resource = find_resource(@resource_type, @resource_id)
        render_not_found unless @resource

        @audit_trail = audit_trail_for(@resource, @organization)
        @entries = @audit_trail.entries
        @changes_by_field = @audit_trail.changes_by_field
      else
        @resource_types = ["List", "ListItem"]
      end
    end

    def export_audit
      @organization = Current.organization
      redirect_to admin_root_path, alert: "Please select an organization first" unless @organization

      @days = params[:days]&.to_i || 90
      @format = params[:format] || "csv"

      events = Event.where(organization_id: @organization.id)
                    .since(@days.days.ago)

      case @format
      when "csv"
        send_data export_audit_trail_csv(@organization, @days), filename: "audit_export_#{@organization.id}_#{Time.current.to_date}.csv"
      when "json"
        @report = compliance_report(@organization)
        send_data @report.to_json, filename: "audit_export_#{@organization.id}_#{Time.current.to_date}.json"
      end
    end

    private

    def find_resource(type, id)
      case type
      when "List"
        List.find_by(id:)
      when "ListItem"
        ListItem.find_by(id:)
      else
        nil
      end
    end

    def export_activity_log_csv(events)
      CSV.generate do |csv|
        csv << ["Timestamp", "Event Type", "Details", "Changes"]

        events.each do |event|
          csv << [
            event.created_at.to_s,
            event.event_type,
            format_event_details(event),
            event.event_data["changes"]&.to_json || ""
          ]
        end
      end
    end

    def format_event_details(event)
      case event.event_type
      when "list_item.created"
        "Created: #{event.event_data['title']}"
      when "list_item.deleted"
        "Deleted: #{event.event_data['title']}"
      when "list_item.assigned"
        "Assigned to user #{event.event_data['assigned_user_id']}"
      else
        event.event_type
      end
    end

    def render_not_found
      render file: "#{Rails.root}/public/404.html", status: :not_found
    end
  end
end
