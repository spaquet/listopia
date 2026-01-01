# spec/support/ruby_llm_stub.rb
# Stub for RubyLLM to prevent initialization during tests

module RubyLLM
  # Stub to prevent RubyLLM initialization in tests
  def self.configure
    yield self if block_given?
  end

  def self.api_key=(key)
    @api_key = key
  end

  def self.api_key
    @api_key ||= 'test_key'
  end

  class Client
    def initialize(*args, **kwargs)
      # Stub
    end
  end
end
