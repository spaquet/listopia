# Factory to dynamically create RubyLLM::Tool subclasses from tool hashes
class AgentToolWrapper
  def self.create_tool_class(tool_hash)
    tool_name = tool_hash[:name]
    tool_description = tool_hash[:description]
    tool_parameters = tool_hash[:parameters]

    # Dynamically create a RubyLLM::Tool subclass
    Class.new(RubyLLM::Tool) do
      class_attribute :_tool_name, :_tool_description, :_tool_parameters

      self._tool_name = tool_name
      self._tool_description = tool_description
      self._tool_parameters = tool_parameters

      # Define the description for RubyLLM
      define_singleton_method(:description) { _tool_description }

      # Define the name for RubyLLM
      define_singleton_method(:name) { _tool_name }

      # Build parameters using RubyLLM's DSL
      define_singleton_method(:build_parameters) do
        if _tool_parameters && _tool_parameters[:properties]
          _tool_parameters[:properties].each do |param_name, param_spec|
            param_type = param_spec[:type] || "string"
            param_required = _tool_parameters[:required]&.include?(param_name)

            # Add parameter to the tool using RubyLLM's param method
            case param_type
            when "string"
              param param_name.to_sym, type: :string, required: param_required
            when "number", "integer"
              param param_name.to_sym, type: :number, required: param_required
            when "boolean"
              param param_name.to_sym, type: :boolean, required: param_required
            when "array"
              param param_name.to_sym, type: :array, required: param_required
            when "object"
              param param_name.to_sym, type: :object, required: param_required
            else
              param param_name.to_sym, type: :string, required: param_required
            end
          end
        end
      end

      # Call parameter building during class definition
      build_parameters

      # Define execute method - this is called when the LLM invokes the tool
      define_method(:execute) do |**kwargs|
        # Return a success indicator for now
        # The actual tool execution is handled by AgentToolExecutorService
        {
          success: true,
          message: "Tool #{_tool_name} executed with args: #{kwargs.inspect}"
        }
      end
    end
  end
end
