# Wraps tool hashes into objects that RubyLLM expects
class AgentToolWrapper
  attr_reader :name, :description, :parameters

  def initialize(tool_hash)
    @name = tool_hash[:name]
    @description = tool_hash[:description]
    @parameters = tool_hash[:parameters]
  end

  # RubyLLM expects these methods
  def params_schema
    @parameters
  end

  def provider_params
    # OpenAI format for function tools
    {
      type: "function",
      function: {
        name: @name,
        description: @description,
        parameters: @parameters
      }
    }
  end
end
