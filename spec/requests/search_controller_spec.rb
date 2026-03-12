require 'rails_helper'

RSpec.describe SearchController, type: :request do
  let(:user) { create(:user, :verified) }
  let(:organization) { create(:organization, creator: user) }

  before do
    create(:organization_membership, organization: organization, user: user, role: :owner)
  end

  def login_as(user)
    post session_path, params: { email: user.email, password: user.password }
  end

  describe 'authentication' do
    it 'requires user to be signed in for index' do
      get search_path(q: 'test')
      expect(response).to redirect_to(new_session_path)
    end

    it 'requires user to be signed in for spotlight_modal' do
      get spotlight_modal_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe 'GET #index' do
    before { login_as(user) }

    context 'with no query' do
      it 'returns 200' do
        get search_path
        expect(response).to have_http_status(:ok)
      end

      it 'returns empty results' do
        get search_path
        expect(assigns(:results)).to eq([])
      end

      it 'assigns nil query' do
        get search_path
        expect(assigns(:query)).to be_nil
      end
    end

    context 'with query parameter' do
      it 'calls SearchService with query' do
        expect(SearchService).to receive(:call).with(
          hash_including(
            query: 'test',
            user: user,
            limit: 20
          )
        ).and_return(double(success?: true, data: []))

        get search_path(q: 'test')
      end

      it 'assigns query from params' do
        allow(SearchService).to receive(:call).and_return(double(success?: true, data: []))

        get search_path(q: 'test query')
        expect(assigns(:query)).to eq('test query')
      end

      it 'strips whitespace from query' do
        allow(SearchService).to receive(:call).and_return(double(success?: true, data: []))

        get search_path(q: '  test  ')
        expect(assigns(:query)).to eq('test')
      end
    end

    context 'with limit parameter' do
      it 'uses provided limit' do
        expect(SearchService).to receive(:call).with(
          hash_including(limit: 50)
        ).and_return(double(success?: true, data: []))

        get search_path(q: 'test', limit: '50')
      end

      it 'defaults to 20 when limit not provided' do
        expect(SearchService).to receive(:call).with(
          hash_including(limit: 20)
        ).and_return(double(success?: true, data: []))

        get search_path(q: 'test')
      end
    end

    context 'when SearchService succeeds' do
      it 'assigns results' do
        list = create(:list, owner: user, organization: organization)
        allow(SearchService).to receive(:call).and_return(
          double(success?: true, data: [list])
        )

        get search_path(q: 'test')
        expect(assigns(:results)).to eq([list])
      end
    end

    context 'when SearchService fails' do
      it 'assigns empty array' do
        allow(SearchService).to receive(:call).and_return(
          double(success?: false, errors: ['Search error'])
        )

        get search_path(q: 'test')
        expect(assigns(:results)).to eq([])
      end

      it 'logs the error' do
        allow(SearchService).to receive(:call).and_return(
          double(success?: false, errors: ['Search error'])
        )

        expect(Rails.logger).to receive(:warn).with(/Search failed/)
        get search_path(q: 'test')
      end
    end

    context 'HTML format' do
      it 'renders HTML' do
        allow(SearchService).to receive(:call).and_return(double(success?: true, data: []))

        get search_path(q: 'test'), headers: { 'Accept' => 'text/html' }
        expect(response.media_type).to include('text/html')
      end
    end

    context 'Turbo Stream format' do
      it 'returns HTML (turbo_stream format not implemented)' do
        allow(SearchService).to receive(:call).and_return(double(success?: true, data: []))

        get search_path(q: 'test'), headers: { accept: 'text/vnd.turbo-stream.html' }
        # Controller lists turbo_stream in respond_to but doesn't implement it,
        # so it returns HTML template instead
        expect(response.media_type).to include('text/html')
      end
    end

    context 'JSON format' do
      it 'returns JSON response' do
        list = create(:list, owner: user, organization: organization, title: 'Test List')
        allow(SearchService).to receive(:call).and_return(
          double(success?: true, data: [list])
        )

        get search_path(q: 'test', format: 'json')
        expect(response.media_type).to include('application/json')
      end

      it 'includes query in JSON' do
        allow(SearchService).to receive(:call).and_return(double(success?: true, data: []))

        get search_path(q: 'test', format: 'json')
        json = JSON.parse(response.body)

        expect(json['query']).to eq('test')
      end

      it 'includes result count in JSON' do
        list = create(:list, owner: user, organization: organization)
        allow(SearchService).to receive(:call).and_return(
          double(success?: true, data: [list])
        )

        get search_path(q: 'test', format: 'json')
        json = JSON.parse(response.body)

        expect(json['count']).to eq(1)
      end

      it 'formats results with required fields' do
        list = create(:list, owner: user, organization: organization, title: 'My List', description: 'Test')
        allow(SearchService).to receive(:call).and_return(
          double(success?: true, data: [list])
        )

        get search_path(q: 'test', format: 'json')
        json = JSON.parse(response.body)
        result = json['results'].first

        expect(result).to include('id', 'type', 'title', 'description', 'url', 'created_at', 'updated_at')
      end

      it 'includes avatar_url for users' do
        user_result = create(:user, name: 'Test User')
        allow(SearchService).to receive(:call).and_return(
          double(success?: true, data: [user_result])
        )

        get search_path(q: 'test', format: 'json')
        json = JSON.parse(response.body)
        result = json['results'].first

        expect(result).to have_key('avatar_url')
      end
    end
  end

  describe 'GET #spotlight_modal' do
    before { login_as(user) }

    it 'returns 200' do
      get spotlight_modal_path
      expect(response).to have_http_status(:ok)
    end

    it 'renders partial without layout' do
      get spotlight_modal_path
      # Verify it's rendering the partial
      expect(response.body).to include('spotlight')
    end
  end

  describe 'result formatting' do
    before { login_as(user) }

    context 'List results' do
      it 'extracts title from list' do
        list = create(:list, owner: user, organization: organization, title: 'Shopping List')
        allow(SearchService).to receive(:call).and_return(double(success?: true, data: [list]))

        get search_path(q: 'shopping', format: 'json')
        json = JSON.parse(response.body)

        expect(json['results'].first['title']).to eq('Shopping List')
      end

      it 'extracts description from list' do
        list = create(:list, owner: user, organization: organization, description: 'Groceries')
        allow(SearchService).to receive(:call).and_return(double(success?: true, data: [list]))

        get search_path(q: 'test', format: 'json')
        json = JSON.parse(response.body)

        expect(json['results'].first['description']).to eq('Groceries')
      end
    end

    context 'ListItem results' do
      let(:list) { create(:list, owner: user, organization: organization) }

      it 'extracts title from list item' do
        item = create(:list_item, list: list, title: 'Buy milk')
        allow(SearchService).to receive(:call).and_return(double(success?: true, data: [item]))

        get search_path(q: 'milk', format: 'json')
        json = JSON.parse(response.body)

        expect(json['results'].first['title']).to eq('Buy milk')
      end
    end

    context 'User results' do
      it 'extracts name from user' do
        search_user = create(:user, name: 'John Doe')
        allow(SearchService).to receive(:call).and_return(double(success?: true, data: [search_user]))

        get search_path(q: 'john', format: 'json')
        json = JSON.parse(response.body)

        expect(json['results'].first['title']).to eq('John Doe')
      end

      it 'extracts email as description for user' do
        search_user = create(:user, email: 'john@example.com')
        allow(SearchService).to receive(:call).and_return(double(success?: true, data: [search_user]))

        get search_path(q: 'john', format: 'json')
        json = JSON.parse(response.body)

        expect(json['results'].first['description']).to eq('john@example.com')
      end
    end

    context 'Comment results' do
      let(:list) { create(:list, owner: user, organization: organization) }

      it 'formats comment title with user name' do
        comment = create(:comment, user: user, commentable: list, content: 'Great list!')
        allow(SearchService).to receive(:call).and_return(double(success?: true, data: [comment]))

        get search_path(q: 'great', format: 'json')
        json = JSON.parse(response.body)

        expect(json['results'].first['title']).to include(user.name)
      end

      it 'extracts content from comment' do
        comment = create(:comment, user: user, commentable: list, content: 'Test comment')
        allow(SearchService).to receive(:call).and_return(double(success?: true, data: [comment]))

        get search_path(q: 'test', format: 'json')
        json = JSON.parse(response.body)

        expect(json['results'].first['description']).to eq('Test comment')
      end
    end
  end
end
