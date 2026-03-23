FactoryBot.define do
  factory :chat_context do
    user { association :user }
    chat { association :chat }
    organization { user.organizations.first || association(:organization, creator: user) }

    state { "initial" }
    status { "pending" }

    request_content { "Create a planning list" }
    detected_intent { "list_creation" }
    intent_confidence { 0.95 }
    planning_domain { "generic" }
    complexity_level { "simple" }
    complexity_reasoning { "Basic request with clear scope" }
    is_complex { false }


    parameters { {} }
    missing_parameters { [] }

    pre_creation_questions { [] }
    pre_creation_answers { {} }

    generated_items { [] }
    hierarchical_items { {} }

    list_created_id { nil }

    metadata { {} }
    error_message { nil }

    trait :simple do
      complexity_level { "simple" }
      is_complex { false }
    end

    trait :complex do
      complexity_level { "complex" }
      is_complex { true }
      state { "pre_creation" }
      status { "awaiting_user_input" }
      pre_creation_questions do
        [
          { id: "1", question: "What is the main goal?", type: "text" },
          { id: "2", question: "What is your timeline?", type: "text" }
        ]
      end
    end

    trait :with_answers do
      state { "pre_creation" }
      pre_creation_answers do
        {
          "1" => "Complete the project",
          "2" => "Within 2 weeks"
        }
      end
    end

    trait :completed do
      state { "completed" }
      status { "complete" }
      list_created_id { SecureRandom.uuid }
    end

    trait :with_parameters do
      parameters do
        {
          locations: [ "New York", "Los Angeles" ],
          budget: "$50,000",
          timeline: "Q2 2026"
        }
      end
    end

    trait :with_parent_requirements do
      hierarchical_items do
        {
          "parent_items" => [
            { title: "Planning", description: "Planning phase", priority: "high" },
            { title: "Execution", description: "Execution phase", priority: "high" }
          ],
          "subdivisions" => {}
        }
      end
    end

    trait :with_hierarchical_items do
      hierarchical_items do
        {
          "parent_items" => [
            { title: "Planning", description: "Planning activities" }
          ],
          "subdivisions" => {
            "Phase 1" => {
              title: "Phase 1",
              items: [
                { title: "Task 1", priority: "high" },
                { title: "Task 2", priority: "medium" }
              ]
            }
          }
        }
      end
    end

    trait :event_planning do
      planning_domain { "event" }
      request_content { "Plan a conference" }
      hierarchical_items do
        {
          "parent_items" => [
            { title: "Pre-Event Planning", description: "Planning before the event", priority: "high" },
            { title: "Logistics & Operations", description: "On-site operations", priority: "high" }
          ],
          "subdivisions" => {}
        }
      end
    end

    trait :project_planning do
      planning_domain { "project" }
      request_content { "Plan a software project" }
      hierarchical_items do
        {
          "parent_items" => [
            { title: "Initiation", description: "Project initiation", priority: "high" },
            { title: "Execution", description: "Project execution", priority: "high" },
            { title: "Monitoring", description: "Project monitoring", priority: "medium" }
          ],
          "subdivisions" => {}
        }
      end
    end

    trait :travel_planning do
      planning_domain { "travel" }
      request_content { "Plan a trip to Europe" }
      hierarchical_items do
        {
          "parent_items" => [
            { title: "Pre-Trip Preparation", description: "Preparation before travel", priority: "high" },
            { title: "During Trip", description: "Activities during trip", priority: "high" },
            { title: "Post-Trip", description: "Activities after trip", priority: "low" }
          ],
          "subdivisions" => {}
        }
      end
    end
  end

  # Backwards compatibility alias
  factory :planning_context, parent: :chat_context
end
