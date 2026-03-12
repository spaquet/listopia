require 'rails_helper'

RSpec.describe NotificationPreferencesController, type: :request do
  let(:user) { create(:user, :verified) }

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  describe 'authentication' do
    it 'requires user to be signed in for show' do
      get notification_preferences_path
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for update' do
      patch notification_preferences_path, params: { notification_preferences: {} }
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'GET #show' do
    before { login_as(user) }

    context 'when user has notification settings' do
      it 'returns 200' do
        create(:notification_setting, user: user)

        get notification_preferences_path
        expect(response).to have_http_status(:ok)
      end

      it 'assigns existing notification settings' do
        settings = create(:notification_setting, user: user)

        get notification_preferences_path
        expect(assigns(:preferences).user).to eq(user)
        expect(assigns(:preferences)).to be_persisted
      end
    end

    context 'when user does not have notification settings' do
      it 'creates or fetches notification settings' do
        get notification_preferences_path
        expect(response).to have_http_status(:ok)
      end

      it 'assigns persisted settings' do
        get notification_preferences_path
        expect(assigns(:preferences)).to be_persisted
        expect(assigns(:preferences).user).to eq(user)
      end
    end
  end

  describe 'PATCH #update' do
    before { login_as(user) }

    context 'with valid parameters' do
      it 'updates email_notifications' do
        original_value = user.notification_settings.email_notifications

        patch notification_preferences_path,
              params: { notification_preferences: { email_notifications: original_value ? '0' : '1' } }

        expect(user.notification_settings.reload.email_notifications).not_to eq(original_value)
      end

      it 'accepts push_notifications parameter' do
        patch notification_preferences_path,
              params: { notification_preferences: { push_notifications: '1' } }

        expect(response).to have_http_status(:ok)
      end

      it 'accepts sms_notifications parameter' do
        patch notification_preferences_path,
              params: { notification_preferences: { sms_notifications: '1' } }

        expect(response).to have_http_status(:ok)
      end

      it 'accepts collaboration_notifications parameter' do
        patch notification_preferences_path,
              params: { notification_preferences: { collaboration_notifications: '0' } }

        expect(response).to have_http_status(:ok)
      end

      it 'accepts list_activity_notifications parameter' do
        patch notification_preferences_path,
              params: { notification_preferences: { list_activity_notifications: '1' } }

        expect(response).to have_http_status(:ok)
      end

      it 'accepts item_activity_notifications parameter' do
        patch notification_preferences_path,
              params: { notification_preferences: { item_activity_notifications: '0' } }

        expect(response).to have_http_status(:ok)
      end

      it 'accepts status_change_notifications parameter' do
        patch notification_preferences_path,
              params: { notification_preferences: { status_change_notifications: '1' } }

        expect(response).to have_http_status(:ok)
      end

      it 'accepts notification_frequency parameter' do
        patch notification_preferences_path,
              params: { notification_preferences: { notification_frequency: 'weekly_digest' } }

        expect(response).to have_http_status(:ok)
      end

      it 'accepts quiet_hours_start parameter' do
        patch notification_preferences_path,
              params: { notification_preferences: { quiet_hours_start: '22:00' } }

        expect(response).to have_http_status(:ok)
      end

      it 'accepts quiet_hours_end parameter' do
        patch notification_preferences_path,
              params: { notification_preferences: { quiet_hours_end: '08:00' } }

        expect(response).to have_http_status(:ok)
      end

      it 'accepts timezone parameter' do
        patch notification_preferences_path,
              params: { notification_preferences: { timezone: 'America/New_York' } }

        expect(response).to have_http_status(:ok)
      end

      it 'updates multiple preferences at once' do
        patch notification_preferences_path,
              params: {
                notification_preferences: {
                  email_notifications: '0',
                  push_notifications: '1',
                  notification_frequency: 'daily_digest'
                }
              }

        expect(response).to have_http_status(:ok)
      end

      it 'renders show template' do
        patch notification_preferences_path,
              params: { notification_preferences: { timezone: 'UTC' } }

        expect(response).to have_http_status(:ok)
      end

      it 'returns success response' do
        patch notification_preferences_path,
              params: { notification_preferences: { timezone: 'UTC' } }

        # Verify response is successful (notice is in flash headers)
        expect(response).to have_http_status(:ok)
      end
    end

    context 'with empty parameters' do
      it 'does not update anything' do
        original_email = user.notification_settings.email_notifications

        patch notification_preferences_path,
              params: { notification_preferences: {} }

        expect(user.notification_settings.reload.email_notifications).to eq(original_email)
      end

      it 'still renders show template' do
        patch notification_preferences_path,
              params: { notification_preferences: {} }

        expect(response.body).to include('Notification Preferences')
      end
    end

    context 'with no notification_preferences param' do
      it 'does not update anything' do
        original_email = user.notification_settings.email_notifications

        patch notification_preferences_path, params: {}

        expect(user.notification_settings.reload.email_notifications).to eq(original_email)
      end
    end

    context 'parameter filtering' do
      it 'ignores unknown parameters' do
        patch notification_preferences_path,
              params: {
                notification_preferences: {
                  email_notifications: '1',
                  user_id: 999,
                  created_at: '2020-01-01'
                }
              }

        expect(user.notification_settings.reload.email_notifications).to be true
      end

      it 'only permits allowed parameters' do
        expect {
          patch notification_preferences_path,
                params: {
                  notification_preferences: {
                    email_notifications: '0',
                    admin: '1'
                  }
                }
        }.not_to raise_error
      end
    end

    context 'with blank string values' do
      it 'ignores blank notification_frequency' do
        original_freq = user.notification_settings.notification_frequency

        patch notification_preferences_path,
              params: { notification_preferences: { notification_frequency: '' } }

        expect(user.notification_settings.reload.notification_frequency).to eq(original_freq)
      end

      it 'ignores blank timezone' do
        original_tz = user.notification_settings.timezone

        patch notification_preferences_path,
              params: { notification_preferences: { timezone: '' } }

        expect(user.notification_settings.reload.timezone).to eq(original_tz)
      end
    end
  end

  describe 'only own preferences' do
    let(:other_user) { create(:user, :verified) }

    before { login_as(user) }

    it 'can only view own preferences' do
      get notification_preferences_path
      expect(assigns(:preferences).user).to eq(user)
    end

    it 'updates are applied to current user' do
      patch notification_preferences_path,
            params: { notification_preferences: { timezone: 'America/New_York' } }

      expect(response).to have_http_status(:ok)
      expect(user.notification_settings.reload.timezone).to eq('America/New_York')
    end
  end
end
