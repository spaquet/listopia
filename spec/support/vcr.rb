# spec/support/vcr.rb
require 'vcr'
require 'webmock'

# Refresh RubyLLM's model registry before running tests
# This ensures models like 'gpt-4o-mini' are recognized
RubyLLM.models.refresh! if defined?(RubyLLM)

WebMock.allow_net_connect!

VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock

  # Default recording mode
  # :none = use cassettes only, don't record new ones
  # :new_episodes = record new cassettes if they don't exist
  # :once = record once then use cassettes
  # :all = always re-record
  config.default_cassette_options = { record: :new_episodes }

  # Filter sensitive data
  if ENV['OPENAI_API_KEY']
    config.filter_sensitive_data('<OPENAI_API_KEY>') { ENV['OPENAI_API_KEY'] }
  end

  # Allow localhost
  config.ignore_localhost = true

  # ADD THIS FOR DEBUGGING
  config.debug_logger = $stderr

  # ADD THIS TOO
  config.define_cassette_placeholder('<OPENAI_API_KEY>', ENV['OPENAI_API_KEY']) if ENV['OPENAI_API_KEY']
end
