require 'rails_helper'

RSpec.describe AnalyticsController, type: :request do
  let(:user) { create(:user, :verified) }
  let(:organization) { create(:organization, creator: user) }
  let(:list) { create(:list, owner: user, organization: organization) }

  before do
    create(:organization_membership, organization: organization, user: user, role: :owner)
  end

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  describe 'authentication' do
    it 'requires user to be signed in' do
      get list_analytics_path(list)
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'authorization' do
    let(:other_user) { create(:user, :verified) }
    let(:other_org) { create(:organization, creator: other_user) }
    let(:other_list) { create(:list, owner: other_user, organization: other_org) }

    before do
      login_as(other_user)
      create(:organization_membership, organization: other_org, user: other_user, role: :owner)
    end

    it 'denies access when user cannot read list' do
      get list_analytics_path(list)
      expect(response).to redirect_to(lists_path)
      expect(flash[:alert]).to include('permission')
    end
  end

  describe 'GET #index' do
    before { login_as(user) }

    it 'returns 200' do
      get list_analytics_path(list)
      expect(response).to have_http_status(:ok)
    end

    it 'assigns analytics_data' do
      get list_analytics_path(list)
      expect(assigns(:analytics_data)).to be_a(Hash)
    end

    it 'includes overview metrics' do
      get list_analytics_path(list)
      analytics = assigns(:analytics_data)
      expect(analytics).to have_key(:overview)
    end

    it 'includes completion analytics' do
      get list_analytics_path(list)
      analytics = assigns(:analytics_data)
      expect(analytics).to have_key(:completion)
    end

    it 'includes productivity analytics' do
      get list_analytics_path(list)
      analytics = assigns(:analytics_data)
      expect(analytics).to have_key(:productivity)
    end

    it 'includes collaboration analytics' do
      get list_analytics_path(list)
      analytics = assigns(:analytics_data)
      expect(analytics).to have_key(:collaboration)
    end

    it 'includes timeline analytics' do
      get list_analytics_path(list)
      analytics = assigns(:analytics_data)
      expect(analytics).to have_key(:timeline)
    end

    it 'includes content analytics' do
      get list_analytics_path(list)
      analytics = assigns(:analytics_data)
      expect(analytics).to have_key(:content)
    end

    it 'includes priority analytics' do
      get list_analytics_path(list)
      analytics = assigns(:analytics_data)
      expect(analytics).to have_key(:priority)
    end

    it 'includes categories insights' do
      get list_analytics_path(list)
      analytics = assigns(:analytics_data)
      expect(analytics).to have_key(:categories)
    end

    context 'overview metrics' do
      it 'includes total_items' do
        get list_analytics_path(list)
        overview = assigns(:analytics_data)[:overview]
        expect(overview).to have_key(:total_items)
      end

      it 'includes completed_items' do
        get list_analytics_path(list)
        overview = assigns(:analytics_data)[:overview]
        expect(overview).to have_key(:completed_items)
      end

      it 'includes pending_items' do
        get list_analytics_path(list)
        overview = assigns(:analytics_data)[:overview]
        expect(overview).to have_key(:pending_items)
      end

      it 'includes completion_rate' do
        get list_analytics_path(list)
        overview = assigns(:analytics_data)[:overview]
        expect(overview).to have_key(:completion_rate)
      end

      it 'includes overdue_items' do
        get list_analytics_path(list)
        overview = assigns(:analytics_data)[:overview]
        expect(overview).to have_key(:overdue_items)
      end

      it 'includes items_with_due_dates' do
        get list_analytics_path(list)
        overview = assigns(:analytics_data)[:overview]
        expect(overview).to have_key(:items_with_due_dates)
      end

      it 'includes assigned_items' do
        get list_analytics_path(list)
        overview = assigns(:analytics_data)[:overview]
        expect(overview).to have_key(:assigned_items)
      end

      context 'with items in the list' do
        let!(:completed_item) { create(:list_item, list: list, status: 'completed') }
        let!(:pending_item) { create(:list_item, list: list, status: 'pending') }

        it 'counts total items correctly' do
          get list_analytics_path(list)
          overview = assigns(:analytics_data)[:overview]
          expect(overview[:total_items]).to eq(2)
        end

        it 'counts completed items correctly' do
          get list_analytics_path(list)
          overview = assigns(:analytics_data)[:overview]
          expect(overview[:completed_items]).to eq(1)
        end

        it 'counts pending items correctly' do
          get list_analytics_path(list)
          overview = assigns(:analytics_data)[:overview]
          expect(overview[:pending_items]).to eq(1)
        end
      end
    end

    context 'completion analytics' do
      it 'includes avg_completion_time_hours' do
        get list_analytics_path(list)
        completion = assigns(:analytics_data)[:completion]
        expect(completion).to have_key(:avg_completion_time_hours)
      end

      it 'includes median_completion_time_hours' do
        get list_analytics_path(list)
        completion = assigns(:analytics_data)[:completion]
        expect(completion).to have_key(:median_completion_time_hours)
      end

      it 'includes completion_by_priority' do
        get list_analytics_path(list)
        completion = assigns(:analytics_data)[:completion]
        expect(completion).to have_key(:completion_by_priority)
      end

      it 'includes completion_by_type' do
        get list_analytics_path(list)
        completion = assigns(:analytics_data)[:completion]
        expect(completion).to have_key(:completion_by_type)
      end

      it 'includes completion_trend' do
        get list_analytics_path(list)
        completion = assigns(:analytics_data)[:completion]
        expect(completion).to have_key(:completion_trend)
      end
    end

    context 'productivity analytics' do
      it 'includes most_productive_day' do
        get list_analytics_path(list)
        productivity = assigns(:analytics_data)[:productivity]
        expect(productivity).to have_key(:most_productive_day)
      end

      it 'includes items_created_last_30_days' do
        get list_analytics_path(list)
        productivity = assigns(:analytics_data)[:productivity]
        expect(productivity).to have_key(:items_created_last_30_days)
      end

      it 'includes items_completed_last_30_days' do
        get list_analytics_path(list)
        productivity = assigns(:analytics_data)[:productivity]
        expect(productivity).to have_key(:items_completed_last_30_days)
      end

      it 'includes overdue_rate' do
        get list_analytics_path(list)
        productivity = assigns(:analytics_data)[:productivity]
        expect(productivity).to have_key(:overdue_rate)
      end

      it 'includes assignment_completion_rate' do
        get list_analytics_path(list)
        productivity = assigns(:analytics_data)[:productivity]
        expect(productivity).to have_key(:assignment_completion_rate)
      end

      it 'includes velocity_trend' do
        get list_analytics_path(list)
        productivity = assigns(:analytics_data)[:productivity]
        expect(productivity).to have_key(:velocity_trend)
      end
    end

    context 'collaboration analytics' do
      it 'includes total_collaborators' do
        get list_analytics_path(list)
        collaboration = assigns(:analytics_data)[:collaboration]
        expect(collaboration).to have_key(:total_collaborators)
      end

      it 'includes permission_breakdown' do
        get list_analytics_path(list)
        collaboration = assigns(:analytics_data)[:collaboration]
        expect(collaboration).to have_key(:permission_breakdown)
      end

      it 'includes contributor_activity' do
        get list_analytics_path(list)
        collaboration = assigns(:analytics_data)[:collaboration]
        expect(collaboration).to have_key(:contributor_activity)
      end

      it 'includes items_by_assignee' do
        get list_analytics_path(list)
        collaboration = assigns(:analytics_data)[:collaboration]
        expect(collaboration).to have_key(:items_by_assignee)
      end

      it 'includes unassigned_items' do
        get list_analytics_path(list)
        collaboration = assigns(:analytics_data)[:collaboration]
        expect(collaboration).to have_key(:unassigned_items)
      end
    end

    context 'timeline analytics' do
      it 'returns array of daily data' do
        get list_analytics_path(list)
        timeline = assigns(:analytics_data)[:timeline]
        expect(timeline).to be_an(Array)
      end

      it 'includes 30 days of data' do
        get list_analytics_path(list)
        timeline = assigns(:analytics_data)[:timeline]
        expect(timeline.length).to be >= 30
      end

      it 'includes date field for each day' do
        get list_analytics_path(list)
        timeline = assigns(:analytics_data)[:timeline]
        expect(timeline.first).to have_key(:date)
      end

      it 'includes items_created for each day' do
        get list_analytics_path(list)
        timeline = assigns(:analytics_data)[:timeline]
        expect(timeline.first).to have_key(:items_created)
      end

      it 'includes items_completed for each day' do
        get list_analytics_path(list)
        timeline = assigns(:analytics_data)[:timeline]
        expect(timeline.first).to have_key(:items_completed)
      end

      it 'includes net_progress for each day' do
        get list_analytics_path(list)
        timeline = assigns(:analytics_data)[:timeline]
        expect(timeline.first).to have_key(:net_progress)
      end
    end

    context 'content analytics' do
      it 'includes by_type' do
        get list_analytics_path(list)
        content = assigns(:analytics_data)[:content]
        expect(content).to have_key(:by_type)
      end

      it 'includes by_category' do
        get list_analytics_path(list)
        content = assigns(:analytics_data)[:content]
        expect(content).to have_key(:by_category)
      end

      it 'includes avg_title_length' do
        get list_analytics_path(list)
        content = assigns(:analytics_data)[:content]
        expect(content).to have_key(:avg_title_length)
      end

      it 'includes items_with_descriptions' do
        get list_analytics_path(list)
        content = assigns(:analytics_data)[:content]
        expect(content).to have_key(:items_with_descriptions)
      end

      it 'includes items_with_urls' do
        get list_analytics_path(list)
        content = assigns(:analytics_data)[:content]
        expect(content).to have_key(:items_with_urls)
      end

      it 'includes items_with_reminders' do
        get list_analytics_path(list)
        content = assigns(:analytics_data)[:content]
        expect(content).to have_key(:items_with_reminders)
      end

      it 'includes items_with_due_dates' do
        get list_analytics_path(list)
        content = assigns(:analytics_data)[:content]
        expect(content).to have_key(:items_with_due_dates)
      end
    end

    context 'priority analytics' do
      it 'includes distribution' do
        get list_analytics_path(list)
        priority = assigns(:analytics_data)[:priority]
        expect(priority).to have_key(:distribution)
      end

      it 'includes completion_by_priority' do
        get list_analytics_path(list)
        priority = assigns(:analytics_data)[:priority]
        expect(priority).to have_key(:completion_by_priority)
      end

      it 'includes overdue_by_priority' do
        get list_analytics_path(list)
        priority = assigns(:analytics_data)[:priority]
        expect(priority).to have_key(:overdue_by_priority)
      end
    end

    context 'categories insights' do
      it 'includes planning category' do
        get list_analytics_path(list)
        categories = assigns(:analytics_data)[:categories]
        expect(categories).to have_key(:planning)
      end

      it 'includes knowledge category' do
        get list_analytics_path(list)
        categories = assigns(:analytics_data)[:categories]
        expect(categories).to have_key(:knowledge)
      end

      it 'includes personal category' do
        get list_analytics_path(list)
        categories = assigns(:analytics_data)[:categories]
        expect(categories).to have_key(:personal)
      end

      it 'includes completion rate for each category' do
        get list_analytics_path(list)
        categories = assigns(:analytics_data)[:categories]
        expect(categories[:planning]).to have_key(:completion_rate)
      end
    end

    context 'JSON format' do
      it 'returns JSON' do
        get list_analytics_path(list, format: 'json')
        expect(response.media_type).to include('application/json')
      end

      it 'includes analytics_data in JSON' do
        get list_analytics_path(list, format: 'json')
        json = JSON.parse(response.body)
        expect(json).to be_a(Hash)
        expect(json).to have_key('overview')
      end

      it 'serializes numeric values correctly' do
        get list_analytics_path(list, format: 'json')
        json = JSON.parse(response.body)
        expect(json['overview']['total_items']).to be_a(Integer)
      end
    end

    context 'HTML format' do
      it 'returns HTML' do
        get list_analytics_path(list)
        expect(response.media_type).to include('text/html')
      end
    end

    context 'when list does not exist' do
      it 'redirects to lists_path' do
        get list_analytics_path('invalid-id')
        expect(response).to redirect_to(lists_path)
        expect(flash[:alert]).to include('not found')
      end
    end

    context 'with completed items' do
      let!(:completed_item) do
        create(:list_item,
          list: list,
          status: 'completed',
          created_at: 1.day.ago,
          status_changed_at: Time.current
        )
      end

      it 'includes completed items in analytics' do
        get list_analytics_path(list)
        overview = assigns(:analytics_data)[:overview]
        expect(overview[:completed_items]).to be >= 1
      end

      it 'calculates completion_rate' do
        get list_analytics_path(list)
        overview = assigns(:analytics_data)[:overview]
        expect(overview[:completion_rate]).to be_a(Float)
      end
    end

    context 'with overdue items' do
      let!(:overdue_item) do
        create(:list_item,
          list: list,
          status: 'pending',
          due_date: 1.day.ago
        )
      end

      it 'counts overdue items' do
        get list_analytics_path(list)
        overview = assigns(:analytics_data)[:overview]
        expect(overview[:overdue_items]).to be >= 1
      end
    end

    context 'with assigned items' do
      let!(:assigned_item) do
        create(:list_item,
          list: list,
          assigned_user: user
        )
      end

      it 'counts assigned items' do
        get list_analytics_path(list)
        overview = assigns(:analytics_data)[:overview]
        expect(overview[:assigned_items]).to be >= 1
      end
    end

    context 'with collaborator' do
      let(:collaborator) { create(:user, :verified) }

      before do
        create(:list_collaboration, list: list, user: collaborator, permission: 'read')
      end

      it 'counts collaborators' do
        get list_analytics_path(list)
        collaboration = assigns(:analytics_data)[:collaboration]
        expect(collaboration[:total_collaborators]).to be >= 1
      end
    end

    context 'list with multiple items' do
      before do
        create_list(:list_item, 5, list: list, status: 'pending')
        create_list(:list_item, 3, list: list, status: 'completed')
      end

      it 'calculates accurate completion rate' do
        get list_analytics_path(list)
        overview = assigns(:analytics_data)[:overview]
        expect(overview[:total_items]).to eq(8)
        expect(overview[:completed_items]).to eq(3)
      end
    end
  end

  describe 'collaborator access' do
    let(:collaborator) { create(:user, :verified) }
    let(:read_only_collaborator) { create(:user, :verified) }

    before do
      create(:list_collaboration, list: list, user: collaborator, permission: 'collaborate')
      create(:list_collaboration, list: list, user: read_only_collaborator, permission: 'read')
    end

    it 'allows read-only collaborators to view analytics' do
      login_as(read_only_collaborator)
      get list_analytics_path(list)
      expect(response).to have_http_status(:ok)
    end

    it 'allows full collaborators to view analytics' do
      login_as(collaborator)
      get list_analytics_path(list)
      expect(response).to have_http_status(:ok)
    end
  end
end
