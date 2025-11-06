# spec/support/vcr.rb
require 'vcr'
require 'webmock'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock

  # CRITICAL: Enforce cassette usage
  # This prevents accidental API calls when cassette is missing
  config.allow_http_connections_when_no_cassette = false

  # Default recording mode
  # In CI: :none (use cassettes, fail if missing)
  # Local: :new_episodes (record if needed, use existing)
  config.default_cassette_options = {
    record: ENV['CI'].present? ? :none : :new_episodes,
    match_requests_on: [ :method, :uri ],
    allow_playback_repeats: true
  }

  # Filter sensitive API keys from cassettes
  if ENV['OPENAI_API_KEY'].present?
    config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
    config.define_cassette_placeholder('<OPENAI_API_KEY>', ENV['OPENAI_API_KEY'])
  end

  if ENV['ANTHROPIC_API_KEY'].present?
    config.filter_sensitive_data('<ANTHROPIC_API_KEY>') { ENV['ANTHROPIC_API_KEY'] }
    config.define_cassette_placeholder('<ANTHROPIC_API_KEY>', ENV['ANTHROPIC_API_KEY'])
  end

  # Allow localhost connections (development servers)
  config.ignore_localhost = true

  # Debug logging for troubleshooting
  if ENV['VCR_DEBUG'].present?
    config.debug_logger = $stderr
  end
end

# WebMock configuration
WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: [ 'chromedriver.chromium.org' ]
)
