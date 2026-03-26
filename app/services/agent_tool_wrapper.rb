# Factory to dynamically create RubyLLM::Tool subclasses from tool hashes
class AgentToolWrapper
  def self.create_tool_class(tool_hash, agent: nil, user: nil, organization: nil, invocable: nil, run: nil)
    tool_name = tool_hash[:name]
    tool_description = tool_hash[:description]
    tool_parameters = tool_hash[:parameters]

    Rails.logger.debug("Creating tool class for: #{tool_name}")

    # Dynamically create a RubyLLM::Tool subclass
    tool_class = Class.new(RubyLLM::Tool) do
      # Call RubyLLM DSL methods at class definition time
      begin
        description tool_description
      rescue => e
        Rails.logger.error("Error setting description for #{tool_name}: #{e.message}")
      end

      # Add parameters using RubyLLM's param DSL
      if tool_parameters && tool_parameters[:properties]
        tool_parameters[:properties].each do |param_name, param_spec|
          begin
            param_type = param_spec[:type] || "string"
            param_desc = param_spec[:description] || param_name.to_s

            # Add parameter to the tool using RubyLLM's param method
            # Note: RubyLLM requires parameters to be passed as positional arguments
            case param_type
            when "string"
              param param_name.to_sym, type: :string, desc: param_desc
            when "number", "integer"
              param param_name.to_sym, type: :number, desc: param_desc
            when "boolean"
              param param_name.to_sym, type: :boolean, desc: param_desc
            when "array"
              param param_name.to_sym, type: :array, desc: param_desc
            when "object"
              param param_name.to_sym, type: :object, desc: param_desc
            else
              param param_name.to_sym, type: :string, desc: param_desc
            end
          rescue => e
            Rails.logger.error("Error adding parameter #{param_name} to #{tool_name}: #{e.message}")
          end
        end
      end

      # Define the name method - RubyLLM uses this to identify the tool
      define_method(:name) { tool_name }

      # Define execute method - this is called when the LLM invokes the tool
      define_method(:execute) do |**kwargs|
        # Actually execute the tool using AgentToolExecutorService
        # Create a tool_call object in the format expected by AgentToolExecutorService

        Rails.logger.debug("Tool #{tool_name} execute called")
        Rails.logger.debug("  kwargs: #{kwargs.inspect}")
        Rails.logger.debug("  kwargs class: #{kwargs.class}")
        Rails.logger.debug("  kwargs keys: #{kwargs.keys.inspect}")

        # Convert kwargs to proper format for AgentToolExecutorService
        # Arguments should be a JSON string
        arguments_json = if kwargs.is_a?(Hash)
                          # Stringify keys just in case they're symbols
                          string_hash = kwargs.transform_keys { |k| k.to_s }
                          string_hash.to_json
                        else
                          kwargs.to_json
                        end

        tool_call_obj = {
          "id" => SecureRandom.uuid,
          "function" => {
            "name" => tool_name,
            "arguments" => arguments_json
          }
        }

        Rails.logger.debug("Tool #{tool_name}: arguments_json: #{arguments_json}")

        # Execute using AgentToolExecutorService if we have the context
        if agent && user && organization
          result = AgentToolExecutorService.call(
            tool_call: tool_call_obj,
            agent: agent,
            user: user,
            organization: organization,
            invocable: invocable,
            run: run
          )

          Rails.logger.debug("Tool #{tool_name} result: #{result.inspect}")

          if result.success?
            result.data.to_json
          else
            { error: result.message }.to_json
          end
        else
          # Fallback if context is not available
          { error: "Tool execution context not available" }.to_json
        end
      end
    end

    Rails.logger.debug("Created tool class: #{tool_class.inspect}")
    tool_class
  end
end
