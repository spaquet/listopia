# spec/support/vcr.rb
require 'vcr'

VCR.configure do |config|
  # Where to store cassettes
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'

  # Hook into webmock to intercept HTTP requests
  config.hook_into :webmock

  # Default recording mode
  # :none = use cassettes only, don't record new ones
  # :new_episodes = record new cassettes if they don't exist
  # :once = record once then use cassettes
  # :all = always re-record
  config.default_cassette_options = { record: :new_episodes }

  # Filter sensitive data from cassettes
  if ENV['OPENAI_API_KEY']
    config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  end
  if ENV['ANTHROPIC_API_KEY']
    config.filter_sensitive_data('<ANTHROPIC_API_KEY>') { ENV['ANTHROPIC_API_KEY'] }
  end

  # Allow localhost connections (for ActionCable, etc)
  config.ignore_localhost = true

  # Ignore specific patterns
  config.ignore_hosts 'raw.githubusercontent.com'
end
