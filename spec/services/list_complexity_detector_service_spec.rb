require "rails_helper"

RSpec.describe ListComplexityDetectorService, type: :service do
  let(:user) { create(:user) }
  let(:organization) { user.organizations.first }
  let(:context) { double("context", user: user, organization: organization) }

  before(:each) do
    # Reset any previous mocks
    RubyLLM::Chat.class_eval { alias_method :original_initialize, :initialize } if !RubyLLM::Chat.instance_variable_defined?(:@original_initialize_aliased)
  end

  def create_service_with_response(message_content, response_data)
    message = create(:message, content: message_content)

    # Set up the mock BEFORE creating the service
    json_response = JSON.generate(response_data)
    mock_response = double(text: json_response)

    # Stub RubyLLM::Chat.new to return a mock that responds to methods
    mock_chat = double(RubyLLM::Chat)
    allow(mock_chat).to receive(:temperature=).and_return(0.3)
    allow(mock_chat).to receive(:add_message).and_return(true)
    allow(mock_chat).to receive(:complete).and_return(mock_response)

    allow(RubyLLM::Chat).to receive(:new).and_return(mock_chat)

    service = described_class.new(user_message: message, context: context)
    service
  end

  describe "#call" do
    describe "multi-location detection" do
      it "detects roadshow as complex" do
        service = create_service_with_response(
          "I need to organize a roadshow visiting SF, NYC, and Boston",
          { "is_complex" => true, "complexity_indicators" => [ "multi_location" ], "confidence" => "high", "reasoning" => "Multi-location event" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be true
        expect(result.data[:complexity_indicators]).to include("multi_location")
      end

      it "detects multi-city tour as complex" do
        service = create_service_with_response(
          "Plan a tour across Paris, London, Berlin, and Amsterdam",
          { "is_complex" => true, "complexity_indicators" => [ "multi_location" ], "confidence" => "high", "reasoning" => "Multi-city tour" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be true
      end

      it "treats single-location trip as simple" do
        service = create_service_with_response(
          "Plan my business trip to New York",
          { "is_complex" => false, "complexity_indicators" => [], "confidence" => "high", "reasoning" => "Single location" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be false
      end
    end

    describe "time-bound detection" do
      it "detects 8-week plan as complex" do
        service = create_service_with_response(
          "Create an 8-week Python learning plan",
          { "is_complex" => true, "complexity_indicators" => [ "time_bound" ], "confidence" => "high", "reasoning" => "Time-bound program" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be true
        expect(result.data[:complexity_indicators]).to include("time_bound")
      end

      it "detects quarterly roadmap as complex" do
        service = create_service_with_response(
          "Build Q1-Q4 product roadmap",
          { "is_complex" => true, "complexity_indicators" => [ "time_bound" ], "confidence" => "high", "reasoning" => "Quarterly structure" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be true
      end

      it "detects 3-month program as complex" do
        service = create_service_with_response(
          "Design a 3-month onboarding program",
          { "is_complex" => true, "complexity_indicators" => [ "time_bound" ], "confidence" => "high", "reasoning" => "3-month program" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be true
      end
    end

    describe "hierarchical detection" do
      it "detects nested modules as complex" do
        service = create_service_with_response(
          "Create a course with modules: Basics, Intermediate, Advanced, each with lessons",
          { "is_complex" => true, "complexity_indicators" => [ "hierarchical" ], "confidence" => "high", "reasoning" => "Nested modules" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be true
        expect(result.data[:complexity_indicators]).to include("hierarchical")
      end

      it "detects phases with milestones as complex" do
        service = create_service_with_response(
          "Plan project with phases: Planning, Design, Development, Testing, Launch",
          { "is_complex" => true, "complexity_indicators" => [ "hierarchical" ], "confidence" => "high", "reasoning" => "Multi-phase project" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be true
      end
    end

    describe "large scope detection" do
      it "detects comprehensive plan as complex" do
        service = create_service_with_response(
          "Create a complete guide to becoming a product manager with books, courses, and projects",
          { "is_complex" => true, "complexity_indicators" => [ "large_scope" ], "confidence" => "high", "reasoning" => "Comprehensive plan" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be true
        expect(result.data[:complexity_indicators]).to include("large_scope")
      end
    end

    describe "simple list detection" do
      it "treats grocery shopping as simple" do
        service = create_service_with_response(
          "Grocery shopping list",
          { "is_complex" => false, "complexity_indicators" => [], "confidence" => "high", "reasoning" => "Simple flat list" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be false
        expect(result.data[:complexity_indicators]).to be_empty
      end

      it "treats daily todo as simple" do
        service = create_service_with_response(
          "My daily to-do list",
          { "is_complex" => false, "complexity_indicators" => [], "confidence" => "high", "reasoning" => "Simple todo" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be false
      end

      it "treats simple checklist as simple" do
        service = create_service_with_response(
          "Packing checklist for weekend trip",
          { "is_complex" => false, "complexity_indicators" => [], "confidence" => "high", "reasoning" => "Simple checklist" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be false
      end

      it "treats bucket list as simple" do
        service = create_service_with_response(
          "My bucket list of places to visit",
          { "is_complex" => false, "complexity_indicators" => [], "confidence" => "high", "reasoning" => "Simple list" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be false
      end
    end

    describe "confidence levels" do
      it "returns high confidence for clear complex case" do
        service = create_service_with_response(
          "Roadshow across 5 US cities over 8 weeks",
          { "is_complex" => true, "complexity_indicators" => [ "multi_location", "time_bound" ], "confidence" => "high", "reasoning" => "Clear complexity" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:confidence]).to eq("high")
      end

      it "returns high confidence for clear simple case" do
        service = create_service_with_response(
          "Grocery list",
          { "is_complex" => false, "complexity_indicators" => [], "confidence" => "high", "reasoning" => "Clear simplicity" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:confidence]).to eq("high")
      end
    end

    describe "reasoning explanation" do
      it "includes reasoning in response" do
        service = create_service_with_response(
          "Organize a multi-city conference",
          { "is_complex" => true, "complexity_indicators" => [ "multi_location" ], "confidence" => "high", "reasoning" => "Multi-city event requires coordination" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:reasoning]).to be_present
        expect(result.data[:reasoning]).to be_a(String)
      end
    end

    describe "error handling" do
      it "defaults to simple list on LLM failure" do
        message = create(:message, content: "Test message")
        allow_any_instance_of(RubyLLM::Chat).to receive(:complete).and_raise("API Error")

        service = described_class.new(user_message: message, context: context)
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be false
        expect(result.data[:confidence]).to eq("low")
        expect(result.data[:reasoning]).to include("Unable to determine")
      end

      it "defaults to simple list on invalid JSON response" do
        message = create(:message, content: "Test message")
        mock_response = double(text: "This is not JSON")
        allow_any_instance_of(RubyLLM::Chat).to receive(:complete).and_return(mock_response)

        service = described_class.new(user_message: message, context: context)
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be false
      end

      it "never crashes the flow" do
        message = create(:message, content: "Test message")
        allow_any_instance_of(RubyLLM::Chat).to receive(:complete).and_raise(StandardError, "Unexpected error")

        service = described_class.new(user_message: message, context: context)
        expect { service.call }.not_to raise_error
        result = service.call
        expect(result.success?).to be true
      end
    end

    describe "multi-language support" do
      it "detects complexity in Spanish" do
        service = create_service_with_response(
          "Necesito organizar una gira por Madrid, Barcelona y Valencia",
          { "is_complex" => true, "complexity_indicators" => [ "multi_location" ], "confidence" => "high", "reasoning" => "Multi-location event in Spanish" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be true
      end

      it "detects complexity in French" do
        service = create_service_with_response(
          "Plan un tour de 4 semaines à travers Paris, Lyon et Marseille",
          { "is_complex" => true, "complexity_indicators" => [ "multi_location", "time_bound" ], "confidence" => "high", "reasoning" => "Multi-location time-bound event in French" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be true
      end
    end

    describe "combined indicators" do
      it "detects multiple complexity indicators" do
        service = create_service_with_response(
          "Create an 8-week bootcamp with phases (weeks 1-2: Basics, weeks 3-5: Intermediate, weeks 6-8: Advanced) across 3 locations",
          { "is_complex" => true, "complexity_indicators" => [ "time_bound", "hierarchical", "multi_location" ], "confidence" => "high", "reasoning" => "Multiple indicators detected" }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:is_complex]).to be true
      end
    end

    describe "edge cases" do
      it "handles very long message" do
        long_content = "This is a very detailed description " * 100
        service = create_service_with_response(
          long_content,
          { "is_complex" => true, "complexity_indicators" => [ "large_scope" ], "confidence" => "high", "reasoning" => "Long detailed description" }
        )
        result = service.call

        expect(result.success?).to be true
      end

      it "handles special characters" do
        service = create_service_with_response(
          "Plan a roadshow: SF, NYC, LA ($$$) & Boston!",
          { "is_complex" => true, "complexity_indicators" => [ "multi_location" ], "confidence" => "high", "reasoning" => "Multi-location with special characters" }
        )
        result = service.call

        expect(result.success?).to be true
      end
    end
  end

  describe "response structure" do
    it "always returns success" do
      service = create_service_with_response(
        "Any message",
        { "is_complex" => false, "complexity_indicators" => [], "confidence" => "high", "reasoning" => "Test" }
      )
      result = service.call

      expect(result.success?).to be true
    end

    it "includes all required fields" do
      service = create_service_with_response(
        "Roadshow across cities",
        { "is_complex" => true, "complexity_indicators" => [ "multi_location" ], "confidence" => "high", "reasoning" => "Multi-city" }
      )
      result = service.call

      expect(result.data).to have_key(:is_complex)
      expect(result.data).to have_key(:complexity_indicators)
      expect(result.data).to have_key(:confidence)
      expect(result.data).to have_key(:reasoning)
    end

    it "returns boolean for is_complex" do
      service = create_service_with_response(
        "Test message",
        { "is_complex" => true, "complexity_indicators" => [], "confidence" => "high", "reasoning" => "Test" }
      )
      result = service.call

      expect(result.data[:is_complex]).to be_in([ true, false ])
    end

    it "returns array for complexity_indicators" do
      service = create_service_with_response(
        "Test message",
        { "is_complex" => false, "complexity_indicators" => [], "confidence" => "high", "reasoning" => "Test" }
      )
      result = service.call

      expect(result.data[:complexity_indicators]).to be_an(Array)
    end

    it "returns valid confidence level" do
      service = create_service_with_response(
        "Test message",
        { "is_complex" => false, "complexity_indicators" => [], "confidence" => "low", "reasoning" => "Test" }
      )
      result = service.call

      expect(result.data[:confidence]).to be_in([ "high", "medium", "low" ])
    end
  end
end
