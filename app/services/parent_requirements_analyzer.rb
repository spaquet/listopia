# app/services/parent_requirements_analyzer.rb
# Analyzes what parent-level items should exist in the main list
# Based on planning domain and extracted parameters
# Provides coordination, tracking, and summary items appropriate for the list type

class ParentRequirementsAnalyzer < ApplicationService
  def initialize(planning_context)
    @planning_context = planning_context
    @planning_domain = planning_context.planning_domain
    @parameters = planning_context.parameters || {}
  end

  def call
    begin
      # Build requirements based on domain
      parent_items = generate_parent_items

      # Update planning context with parent requirements in hierarchical_items
      hierarchical_items = @planning_context.hierarchical_items || {}
      hierarchical_items["parent_items"] = parent_items
      hierarchical_items["parent_reasoning"] = generate_reasoning
      hierarchical_items["parent_generated_at"] = Time.current.iso8601

      # Also update parent_requirements field for direct access
      parent_requirements = {
        "items" => parent_items,
        "reasoning" => generate_reasoning,
        "generated_at" => Time.current.iso8601
      }

      @planning_context.update!(
        hierarchical_items: hierarchical_items,
        parent_requirements: parent_requirements
      )

      success(data: {
        parent_items: parent_items,
        planning_context: @planning_context
      })
    rescue StandardError => e
      Rails.logger.error("ParentRequirementsAnalyzer error: #{e.class} - #{e.message}")
      failure(errors: [ e.message ])
    end
  end

  private

  def generate_parent_items
    case @planning_domain
    when "event", "roadshow", "conference"
      generate_event_items
    when "project", "sprint", "milestone"
      generate_project_items
    when "vacation", "trip", "travel"
      generate_travel_items
    when "learning", "course", "training"
      generate_learning_items
    when "personal", "shopping", "household"
      generate_personal_items
    else
      generate_generic_items
    end
  end

  def generate_event_items
    [
      {
        title: "Pre-Event Planning",
        description: "Budget approval, vendor selection, venue confirmation",
        type: "section",
        priority: "high"
      },
      {
        title: "Logistics & Operations",
        description: "Scheduling, resource allocation, team coordination",
        type: "section",
        priority: "high"
      },
      {
        title: "Marketing & Promotion",
        description: "Outreach, communications, social media strategy",
        type: "section",
        priority: "medium"
      },
      {
        title: "Post-Event Follow-up",
        description: "Feedback collection, thank-yous, performance analysis",
        type: "section",
        priority: "medium"
      }
    ]
  end

  def generate_project_items
    [
      {
        title: "Project Initialization",
        description: "Define scope, goals, and success criteria",
        type: "section",
        priority: "high"
      },
      {
        title: "Resource & Team Setup",
        description: "Assign roles, allocate budget, plan timeline",
        type: "section",
        priority: "high"
      },
      {
        title: "Development & Execution",
        description: "Core work, milestones, deliverables",
        type: "section",
        priority: "high"
      },
      {
        title: "Review & Closure",
        description: "Testing, documentation, project retrospective",
        type: "section",
        priority: "medium"
      }
    ]
  end

  def generate_travel_items
    [
      {
        title: "Trip Planning",
        description: "Destination research, dates, budget",
        type: "section",
        priority: "high"
      },
      {
        title: "Accommodations & Transport",
        description: "Flights, hotels, ground transportation",
        type: "section",
        priority: "high"
      },
      {
        title: "Itinerary & Activities",
        description: "Must-see attractions, reservations, daily schedule",
        type: "section",
        priority: "medium"
      },
      {
        title: "Pre-Departure Checklist",
        description: "Packing, documents, notifications",
        type: "section",
        priority: "medium"
      }
    ]
  end

  def generate_learning_items
    [
      {
        title: "Course Overview & Goals",
        description: "Learning objectives, resources, timeline",
        type: "section",
        priority: "high"
      },
      {
        title: "Foundational Knowledge",
        description: "Prerequisites, core concepts, fundamentals",
        type: "section",
        priority: "high"
      },
      {
        title: "Advanced Topics",
        description: "Intermediate and advanced material",
        type: "section",
        priority: "medium"
      },
      {
        title: "Practice & Assessment",
        description: "Projects, assignments, evaluations",
        type: "section",
        priority: "medium"
      }
    ]
  end

  def generate_personal_items
    [
      {
        title: "Planning & Preparation",
        description: "Determine needs, compare options, set budget",
        type: "section",
        priority: "high"
      },
      {
        title: "Research & Selection",
        description: "Evaluate choices, read reviews, make decisions",
        type: "section",
        priority: "high"
      },
      {
        title: "Procurement",
        description: "Purchase items or gather supplies",
        type: "section",
        priority: "medium"
      },
      {
        title: "Execution & Follow-up",
        description: "Implementation, returns, satisfaction check",
        type: "section",
        priority: "medium"
      }
    ]
  end

  def generate_generic_items
    [
      {
        title: "Planning",
        description: "Define scope, goals, and timeline",
        type: "section",
        priority: "high"
      },
      {
        title: "Execution",
        description: "Core work and implementation",
        type: "section",
        priority: "high"
      },
      {
        title: "Review & Closure",
        description: "Assessment and final adjustments",
        type: "section",
        priority: "medium"
      }
    ]
  end

  def generate_reasoning
    "Parent items generated based on #{@planning_domain} planning domain. " \
    "These items provide high-level coordination, tracking, and summary functions."
  end
end
