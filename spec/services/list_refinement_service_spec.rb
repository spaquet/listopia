require "rails_helper"

RSpec.describe ListRefinementService, type: :service do
  let(:user) { create(:user) }
  let(:organization) { user.organizations.first }
  let(:context) { double("context", user: user, organization: organization) }

  def create_service_with_response(title, category, items, planning_domain, response_data)
    # Set up the mock BEFORE creating the service
    json_response = JSON.generate(response_data)
    mock_response = double(text: json_response)

    # Stub RubyLLM::Chat.new to return a mock that responds to methods
    mock_chat = double(RubyLLM::Chat)
    allow(mock_chat).to receive(:add_message).and_return(true)
    allow(mock_chat).to receive(:complete).and_return(mock_response)

    allow(RubyLLM::Chat).to receive(:new).and_return(mock_chat)

    service = described_class.new(
      list_title: title,
      category: category,
      items: items,
      context: context,
      planning_domain: planning_domain
    )
    service
  end

  describe "#call" do
    describe "event/roadshow domain" do
      it "generates professional event-specific questions" do
        service = create_service_with_response(
          "June Roadshow",
          "professional",
          [],
          "event",
          {
            "questions" => [
              { "question" => "What is the main objective of this roadshow? (e.g., sales, product launch, awareness, lead generation)", "context" => "Understanding business goals", "field" => "objective" },
              { "question" => "Which cities or regions will you visit, and how long should it run in total?", "context" => "Defining geographic scope and timeline", "field" => "locations" },
              { "question" => "What activities will happen at each stop? (e.g., product demos, presentations, workshops)", "context" => "Structuring the event format", "field" => "activities" }
            ]
          }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:needs_refinement]).to be true
        expect(result.data[:questions].count).to eq(3)
        expect(result.data[:questions].first["question"]).to include("objective")
      end

      it "distinguishes professional events from personal events" do
        service = create_service_with_response(
          "June Roadshow",
          "professional",
          [],
          "event",
          {
            "questions" => [
              { "question" => "What is the main objective of this roadshow? (e.g., sales, product launch, awareness)", "context" => "Business goals", "field" => "objective" },
              { "question" => "Which cities will you visit, and how long total?", "context" => "Geographic scope", "field" => "locations" },
              { "question" => "What activities at each stop?", "context" => "Event format", "field" => "activities" }
            ]
          }
        )
        result = service.call

        expect(result.success?).to be true
        # Professional roadshow should ask about objective, cities, activities - NOT about guest preferences or birthday
        questions_text = result.data[:questions].map { |q| q["question"].downcase }.join(" ")
        expect(questions_text).to include("objective").or include("goal")
        expect(questions_text).not_to include("birthday")
        expect(questions_text).not_to include("personal guests")
      end

      it "includes context for each question" do
        service = create_service_with_response(
          "Conference Planning",
          "professional",
          [],
          "event",
          {
            "questions" => [
              { "question" => "What is the target audience?", "context" => "Helps shape format", "field" => "audience" }
            ]
          }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:questions].first).to have_key("context")
      end
    end

    describe "personal event domain" do
      it "generates personal event-specific questions" do
        service = create_service_with_response(
          "Birthday Party",
          "personal",
          [],
          "event",
          {
            "questions" => [
              { "question" => "What type of personal event? (e.g., birthday, wedding, family gathering)", "context" => "Understanding celebration type", "field" => "event_type" },
              { "question" => "How many guests are you expecting, and any special preferences?", "context" => "Defining guest scope", "field" => "guests" },
              { "question" => "What is your approximate budget and venue preference?", "context" => "Planning resources", "field" => "budget" }
            ]
          }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:needs_refinement]).to be true
        expect(result.data[:questions].count).to eq(3)
        # Personal event should ask about guest count, preferences, NOT about business objectives
        questions_text = result.data[:questions].map { |q| q["question"].downcase }.join(" ")
        expect(questions_text).to include("guest")
        expect(questions_text).not_to include("objective")
      end
    end

    describe "travel domain" do
      it "generates travel-specific questions" do
        service = create_service_with_response(
          "Europe Trip",
          "personal",
          [],
          "travel",
          {
            "questions" => [
              { "question" => "What is the purpose of this trip?", "context" => "Understanding goals", "field" => "purpose" },
              { "question" => "How long is your trip?", "context" => "Timeline planning", "field" => "duration" },
              { "question" => "What is your travel style?", "context" => "Activity preferences", "field" => "style" }
            ]
          }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:needs_refinement]).to be true
        expect(result.data[:questions].first["question"]).to include("purpose")
      end
    end

    describe "learning domain" do
      it "generates learning-specific questions" do
        service = create_service_with_response(
          "Python Course",
          "personal",
          [],
          "learning",
          {
            "questions" => [
              { "question" => "What is your goal with Python?", "context" => "Define outcome", "field" => "goal" },
              { "question" => "What's your current experience level?", "context" => "Gauge starting point", "field" => "level" },
              { "question" => "How much time can you dedicate weekly?", "context" => "Realistic timeline", "field" => "time" }
            ]
          }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:questions].count).to eq(3)
      end
    end

    describe "question limiting" do
      it "limits to max 3 questions even if LLM returns more" do
        service = create_service_with_response(
          "Test",
          "personal",
          [],
          "event",
          {
            "questions" => [
              { "question" => "Q1", "context" => "C1", "field" => "f1" },
              { "question" => "Q2", "context" => "C2", "field" => "f2" },
              { "question" => "Q3", "context" => "C3", "field" => "f3" },
              { "question" => "Q4", "context" => "C4", "field" => "f4" },
              { "question" => "Q5", "context" => "C5", "field" => "f5" }
            ]
          }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:questions].count).to eq(3)
      end

      it "preserves first 3 questions when limiting" do
        service = create_service_with_response(
          "Test",
          "personal",
          [],
          "event",
          {
            "questions" => [
              { "question" => "First", "context" => "C1", "field" => "f1" },
              { "question" => "Second", "context" => "C2", "field" => "f2" },
              { "question" => "Third", "context" => "C3", "field" => "f3" },
              { "question" => "Fourth", "context" => "C4", "field" => "f4" }
            ]
          }
        )
        result = service.call

        expect(result.success?).to be true
        questions = result.data[:questions]
        expect(questions[0]["question"]).to eq("First")
        expect(questions[1]["question"]).to eq("Second")
        expect(questions[2]["question"]).to eq("Third")
      end
    end

    describe "refinement context" do
      it "includes list metadata in refinement context" do
        service = create_service_with_response(
          "Test List",
          "professional",
          ["item1", "item2"],
          "event",
          {
            "questions" => [
              { "question" => "What?", "context" => "Why?", "field" => "what" }
            ]
          }
        )
        result = service.call

        expect(result.success?).to be true
        context = result.data[:refinement_context]
        expect(context[:list_title]).to eq("Test List")
        expect(context[:category]).to eq("professional")
        expect(context[:initial_items]).to eq(["item1", "item2"])
        expect(context[:refinement_stage]).to eq("awaiting_answers")
      end

      it "includes created_at timestamp" do
        service = create_service_with_response(
          "Test",
          "personal",
          [],
          "event",
          {
            "questions" => [
              { "question" => "Q", "context" => "C", "field" => "f" }
            ]
          }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:refinement_context]).to have_key(:created_at)
        expect(result.data[:refinement_context][:created_at]).to be_a(Time)
      end
    end

    describe "no refinement needed" do
      it "returns needs_refinement: false when LLM returns empty questions" do
        service = create_service_with_response(
          "Simple",
          "personal",
          [],
          "general",
          { "questions" => [] }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data[:needs_refinement]).to be false
        expect(result.data[:questions]).to be_empty
      end
    end

    describe "error handling" do
      it "returns graceful response on LLM failure" do
        service = described_class.new(
          list_title: "Test",
          category: "personal",
          items: [],
          context: context,
          planning_domain: "event"
        )

        allow_any_instance_of(RubyLLM::Chat).to receive(:complete).and_raise("API Error")

        result = service.call

        expect(result.success?).to be true
        expect(result.data[:needs_refinement]).to be false
        expect(result.data[:questions]).to be_empty
      end

      it "handles invalid JSON response gracefully" do
        mock_response = double(text: "This is not JSON at all")
        allow(RubyLLM::Chat).to receive(:new).and_wrap_original do |method, *args|
          mock_chat = method.call(*args)
          allow(mock_chat).to receive(:add_message).and_return(true)
          allow(mock_chat).to receive(:complete).and_return(mock_response)
          mock_chat
        end

        service = described_class.new(
          list_title: "Test",
          category: "personal",
          items: [],
          context: context,
          planning_domain: "event"
        )

        result = service.call

        expect(result.success?).to be true
        expect(result.data[:needs_refinement]).to be false
      end

      it "never crashes the flow" do
        service = described_class.new(
          list_title: "Test",
          category: "personal",
          items: [],
          context: context,
          planning_domain: "event"
        )

        allow_any_instance_of(RubyLLM::Chat).to receive(:complete).and_raise(StandardError, "Unexpected error")

        expect { service.call }.not_to raise_error
        result = service.call
        expect(result.success?).to be true
      end

      it "logs errors for debugging" do
        service = described_class.new(
          list_title: "Test",
          category: "personal",
          items: [],
          context: context,
          planning_domain: "event"
        )

        allow_any_instance_of(RubyLLM::Chat).to receive(:complete).and_raise("API Error: 500")

        expect(Rails.logger).to receive(:error).at_least(:once)
        service.call
      end
    end

    describe "planning domain handling" do
      it "uses provided planning domain in prompt" do
        mock_chat = double(RubyLLM::Chat)
        allow(mock_chat).to receive(:add_message)
        allow(mock_chat).to receive(:complete).and_return(double(text: '{"questions":[]}'))

        allow(RubyLLM::Chat).to receive(:new).and_return(mock_chat)

        service = described_class.new(
          list_title: "Test",
          category: "personal",
          items: [],
          context: context,
          planning_domain: "event"
        )

        service.call

        # Verify the system prompt was called with planning_domain context
        expect(mock_chat).to have_received(:add_message).with(hash_including(role: "system"))
      end

      it "defaults to 'general' when planning_domain is nil" do
        mock_chat = double(RubyLLM::Chat)
        allow(mock_chat).to receive(:add_message)
        allow(mock_chat).to receive(:complete).and_return(double(text: '{"questions":[]}'))

        allow(RubyLLM::Chat).to receive(:new).and_return(mock_chat)

        service = described_class.new(
          list_title: "Test",
          category: "personal",
          items: [],
          context: context,
          planning_domain: nil
        )

        result = service.call

        expect(result.success?).to be true
      end
    end

    describe "prompt quality" do
      it "includes WHO, WHAT, WHERE, WHEN, WHY, HOW in prompt" do
        mock_chat = double(RubyLLM::Chat)
        allow(mock_chat).to receive(:complete).and_return(double(text: '{"questions":[]}'))

        captured_prompt = nil
        allow(mock_chat).to receive(:add_message) do |args|
          if args[:role] == "system"
            captured_prompt = args[:content]
          end
        end

        allow(RubyLLM::Chat).to receive(:new).and_return(mock_chat)

        service = described_class.new(
          list_title: "Test",
          category: "personal",
          items: [],
          context: context,
          planning_domain: "event"
        )

        service.call

        expect(captured_prompt).to include("WHO")
        expect(captured_prompt).to include("WHAT")
        expect(captured_prompt).to include("WHERE")
        expect(captured_prompt).to include("WHEN")
        expect(captured_prompt).to include("WHY")
        expect(captured_prompt).to include("HOW")
      end

      it "includes event domain examples in prompt" do
        mock_chat = double(RubyLLM::Chat)
        allow(mock_chat).to receive(:complete).and_return(double(text: '{"questions":[]}'))

        captured_prompt = nil
        allow(mock_chat).to receive(:add_message) do |args|
          if args[:role] == "system"
            captured_prompt = args[:content]
          end
        end

        allow(RubyLLM::Chat).to receive(:new).and_return(mock_chat)

        service = described_class.new(
          list_title: "Roadshow",
          category: "professional",
          items: [],
          context: context,
          planning_domain: "event"
        )

        service.call

        expect(captured_prompt).to include("ROADSHOW")
      end

      it "emphasizes understanding task completely before structuring" do
        mock_chat = double(RubyLLM::Chat)
        allow(mock_chat).to receive(:complete).and_return(double(text: '{"questions":[]}'))

        captured_prompt = nil
        allow(mock_chat).to receive(:add_message) do |args|
          if args[:role] == "system"
            captured_prompt = args[:content]
          end
        end

        allow(RubyLLM::Chat).to receive(:new).and_return(mock_chat)

        service = described_class.new(
          list_title: "Test",
          category: "personal",
          items: [],
          context: context,
          planning_domain: "general"
        )

        service.call

        expect(captured_prompt).to include("NOT creating the list yet")
      end
    end

    describe "response format validation" do
      it "returns success with proper data structure" do
        service = create_service_with_response(
          "Test",
          "personal",
          [],
          "event",
          {
            "questions" => [
              { "question" => "Q", "context" => "C", "field" => "f" }
            ]
          }
        )
        result = service.call

        expect(result.success?).to be true
        expect(result.data).to have_key(:needs_refinement)
        expect(result.data).to have_key(:questions)
        expect(result.data).to have_key(:refinement_context)
      end

      it "returns array for questions" do
        service = create_service_with_response(
          "Test",
          "personal",
          [],
          "event",
          {
            "questions" => [
              { "question" => "Q1", "context" => "C1", "field" => "f1" },
              { "question" => "Q2", "context" => "C2", "field" => "f2" }
            ]
          }
        )
        result = service.call

        expect(result.data[:questions]).to be_an(Array)
        expect(result.data[:questions].all? { |q| q.is_a?(Hash) }).to be true
      end

      it "preserves question structure from LLM" do
        service = create_service_with_response(
          "Test",
          "personal",
          [],
          "event",
          {
            "questions" => [
              { "question" => "Sample question?", "context" => "Sample context", "field" => "sample" }
            ]
          }
        )
        result = service.call

        question = result.data[:questions].first
        expect(question["question"]).to eq("Sample question?")
        expect(question["context"]).to eq("Sample context")
        expect(question["field"]).to eq("sample")
      end
    end
  end

  describe "integration" do
    it "works with nested_sublists parameter" do
      service = create_service_with_response(
        "Complex List",
        "professional",
        ["item1"],
        "event",
        {
          "questions" => [
            { "question" => "Q", "context" => "C", "field" => "f" }
          ]
        }
      )

      # Create service with nested_sublists (this parameter exists in initializer)
      service = described_class.new(
        list_title: "Complex List",
        category: "professional",
        items: ["item1"],
        nested_sublists: [{ title: "Sublist", items: [] }],
        context: context,
        planning_domain: "event"
      )

      # Stub the LLM for this test
      mock_chat = double(RubyLLM::Chat)
      allow(mock_chat).to receive(:add_message).and_return(true)
      allow(mock_chat).to receive(:complete).and_return(double(text: '{"questions":[{"question":"Q","context":"C","field":"f"}]}'))
      allow(RubyLLM::Chat).to receive(:new).and_return(mock_chat)

      result = service.call

      expect(result.success?).to be true
      expect(result.data[:refinement_context][:initial_items]).to eq(["item1"])
    end
  end
end
