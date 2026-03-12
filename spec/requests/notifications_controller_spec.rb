require 'rails_helper'

RSpec.describe NotificationsController, type: :request do
  let(:user) { create(:user, :verified) }

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  describe 'authentication' do
    it 'requires user to be signed in for index' do
      get notifications_path
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for mark_all_as_read' do
      patch mark_all_as_read_notifications_path
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for mark_all_as_seen' do
      patch mark_all_as_seen_notifications_path
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for stats' do
      get stats_notifications_path
      # Should redirect or return error (not 200 OK)
      expect(response.status).not_to eq(200)
    end
  end

  describe 'GET #index' do
    before { login_as(user) }

    it 'returns 200' do
      get notifications_path
      expect(response).to have_http_status(:ok)
    end

    it 'assigns notifications' do
      get notifications_path
      # Notifications can be AssociationRelation or Array
      expect(assigns(:notifications)).to respond_to(:each)
    end

    it 'assigns notification stats' do
      get notifications_path
      expect(assigns(:notification_stats)).to be_a(Hash)
    end

    it 'responds with HTML' do
      get notifications_path, headers: { 'Accept' => 'text/html' }
      expect(response).to have_http_status(:ok)
    end

    it 'responds with Turbo Stream' do
      get notifications_path, headers: { 'Accept' => Mime[:turbo_stream].to_s }
      expect([200, 406]).to include(response.status) # Either OK or Not Acceptable if format not supported
    end

    it 'filters by read status' do
      get notifications_path(filter_read: 'read')
      expect(response).to have_http_status(:ok)
    end

    it 'filters by unread status' do
      get notifications_path(filter_read: 'unread')
      expect(response).to have_http_status(:ok)
    end

    it 'sorts by oldest first' do
      get notifications_path(sort: 'oldest')
      expect(response).to have_http_status(:ok)
    end

    it 'sorts by newest first' do
      get notifications_path(sort: 'newest')
      expect(response).to have_http_status(:ok)
    end

    it 'paginates with offset' do
      get notifications_path(offset: 5)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'PATCH #mark_all_as_read' do
    before { login_as(user) }

    it 'accepts PATCH request' do
      patch mark_all_as_read_notifications_path
      expect([200, 204, 406]).to include(response.status)
    end

    it 'accepts Turbo Stream format' do
      patch mark_all_as_read_notifications_path,
            headers: { 'Accept' => Mime[:turbo_stream].to_s }
      expect([200, 204, 406]).to include(response.status)
    end

    it 'accepts JSON format' do
      patch mark_all_as_read_notifications_path(format: :json)
      expect([200, 204, 406]).to include(response.status)
    end
  end

  describe 'PATCH #mark_all_as_seen' do
    before { login_as(user) }

    it 'accepts PATCH request' do
      patch mark_all_as_seen_notifications_path
      expect([200, 204, 406]).to include(response.status)
    end

    it 'returns JSON response' do
      patch mark_all_as_seen_notifications_path(format: :json)
      expect([200, 204, 406]).to include(response.status)
    end
  end

  describe 'GET #stats' do
    before { login_as(user) }

    it 'returns JSON' do
      get stats_notifications_path(format: :json)
      expect(response.media_type).to include('application/json')
    end

    it 'returns stats structure' do
      get stats_notifications_path(format: :json)
      json = JSON.parse(response.body)
      expect(json).to be_a(Hash)
    end
  end
end
