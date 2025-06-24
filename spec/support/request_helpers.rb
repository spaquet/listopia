# spec/support/request_helpers.rb
module RequestHelpers
  # Helper to parse JSON response
  def json_response
    JSON.parse(response.body)
  end

  # Helper to assert flash messages
  def expect_flash(type, message = nil)
    expect(flash[type]).to be_present
    expect(flash[type]).to include(message) if message
  end

  # Helper to expect successful redirect
  def expect_redirect_to(path)
    expect(response).to have_http_status(:redirect)
    expect(response).to redirect_to(path)
  end

  # Helper for Turbo Stream responses
  def expect_turbo_stream_response
    expect(response.media_type).to eq(Mime[:turbo_stream])
  end

  # Helper to extract Turbo Stream actions
  def turbo_stream_actions
    doc = Nokogiri::HTML(response.body)
    doc.css('turbo-stream').map { |node| node['action'] }
  end

  # Helper to assert specific Turbo Stream action
  def expect_turbo_stream_action(action, target = nil)
    doc = Nokogiri::HTML(response.body)
    stream = if target
      doc.css("turbo-stream[action='#{action}'][target='#{target}']")
    else
      doc.css("turbo-stream[action='#{action}']")
    end
    expect(stream).to be_present
  end
end
