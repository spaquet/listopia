# spec/helpers/item_types_helper_spec.rb
require 'rails_helper'

RSpec.describe ItemTypesHelper, type: :helper do
  describe "#item_type_config" do
    it "returns config for task type" do
      config = helper.item_type_config(:task)
      expect(config).to have_key(:label)
      expect(config).to have_key(:icon_path)
      expect(config).to have_key(:color)
      expect(config).to have_key(:category)
      expect(config).to have_key(:supports)
    end

    it "returns config for idea type" do
      config = helper.item_type_config(:idea)
      expect(config[:label]).to eq("Idea")
      expect(config[:category]).to eq(:knowledge)
    end

    it "returns config for note type" do
      config = helper.item_type_config(:note)
      expect(config[:label]).to eq("Note")
      expect(config[:category]).to eq(:knowledge)
    end

    it "returns config for habit type" do
      config = helper.item_type_config(:habit)
      expect(config[:label]).to eq("Habit")
      expect(config[:category]).to eq(:personal)
    end

    it "returns default task config for unknown type" do
      config = helper.item_type_config(:unknown)
      expect(config[:label]).to eq("Task")
    end

    it "handles string input by converting to symbol" do
      config = helper.item_type_config("task")
      expect(config[:label]).to eq("Task")
    end
  end

  describe "#item_type_label" do
    it "returns label for task" do
      expect(helper.item_type_label(:task)).to eq("Task")
    end

    it "returns label for idea" do
      expect(helper.item_type_label(:idea)).to eq("Idea")
    end

    it "returns label for all supported types" do
      ItemTypesHelper::ITEM_TYPE_CONFIG.keys.each do |type_key|
        label = helper.item_type_label(type_key)
        expect(label).to be_a(String)
        expect(label).not_to be_empty
      end
    end
  end

  describe "#item_type_description" do
    it "returns description for task" do
      description = helper.item_type_description(:task)
      expect(description).to be_a(String)
      expect(description).not_to be_empty
    end

    it "returns description for idea" do
      description = helper.item_type_description(:idea)
      expect(description).to include("concept")
    end

    it "returns descriptions for all supported types" do
      ItemTypesHelper::ITEM_TYPE_CONFIG.keys.each do |type_key|
        description = helper.item_type_description(type_key)
        expect(description).to be_a(String)
      end
    end
  end

  describe "#item_type_icon_svg" do
    it "generates SVG for task type" do
      result = helper.item_type_icon_svg(:task)
      expect(result).to include("<svg")
      expect(result).to include("<path")
      expect(result).to include("d=")
    end

    it "includes stroke attributes" do
      result = helper.item_type_icon_svg(:task)
      expect(result).to include('stroke="currentColor"')
      expect(result).to include('viewBox="0 0 24 24"')
    end

    it "includes color class from config" do
      result = helper.item_type_icon_svg(:task)
      config = helper.item_type_config(:task)
      expect(result).to include(config[:color])
    end

    it "uses custom CSS class when provided" do
      result = helper.item_type_icon_svg(:task, css_class: "w-10 h-10")
      expect(result).to include("w-10 h-10")
    end

    it "uses default w-5 h-5 when no class provided" do
      result = helper.item_type_icon_svg(:task)
      expect(result).to include("w-5 h-5")
    end

    it "includes stroke-linecap and stroke-linejoin" do
      result = helper.item_type_icon_svg(:task)
      expect(result).to include("stroke_linecap")
      expect(result).to include("stroke_linejoin")
      expect(result).to include("stroke_width")
    end
  end

  describe "#item_type_category" do
    it "returns planning category for task" do
      expect(helper.item_type_category(:task)).to eq(:planning)
    end

    it "returns knowledge category for idea" do
      expect(helper.item_type_category(:idea)).to eq(:knowledge)
    end

    it "returns personal category for habit" do
      expect(helper.item_type_category(:habit)).to eq(:personal)
    end

    it "returns correct category for all types" do
      ItemTypesHelper::ITEM_TYPE_CONFIG.keys.each do |type_key|
        category = helper.item_type_category(type_key)
        expect([ :planning, :knowledge, :personal ]).to include(category)
      end
    end
  end

  describe "#item_type_supports?" do
    it "returns true when feature is supported" do
      expect(helper.item_type_supports?(:task, :completion)).to be(true)
    end

    it "returns false when feature is not supported" do
      expect(helper.item_type_supports?(:idea, :completion)).to be(false)
    end

    it "checks completion support correctly" do
      expect(helper.item_type_supports?(:task, :completion)).to be(true)
      expect(helper.item_type_supports?(:idea, :completion)).to be(false)
    end

    it "checks due_date support correctly" do
      expect(helper.item_type_supports?(:task, :due_date)).to be(true)
      expect(helper.item_type_supports?(:idea, :due_date)).to be(false)
    end

    it "checks assignment support correctly" do
      expect(helper.item_type_supports?(:task, :assignment)).to be(true)
      expect(helper.item_type_supports?(:idea, :assignment)).to be(false)
    end

    it "checks priority support correctly" do
      expect(helper.item_type_supports?(:task, :priority)).to be(true)
      expect(helper.item_type_supports?(:note, :priority)).to be(false)
    end

    it "returns false for unsupported feature type" do
      expect(helper.item_type_supports?(:task, :unknown_feature)).to be(false)
    end
  end

  describe "#item_type_options_for_select" do
    it "returns array of options" do
      result = helper.item_type_options_for_select
      expect(result).to be_an(Array)
      expect(result).not_to be_empty
    end

    it "returns label-value pairs" do
      result = helper.item_type_options_for_select
      result.each do |option|
        expect(option).to be_an(Array)
        expect(option.length).to eq(2)
      end
    end

    it "includes task option" do
      result = helper.item_type_options_for_select
      labels = result.map(&:first)
      expect(labels).to include("Task")
    end

    it "returns grouped options when grouped is true" do
      result = helper.item_type_options_for_select(grouped: true)
      expect(result).to be_a(Hash)
      expect(result).to have_key("Planning")
      expect(result).to have_key("Knowledge")
      expect(result).to have_key("Personal")
    end

    it "groups options correctly" do
      result = helper.item_type_options_for_select(grouped: true)
      expect(result["Planning"]).to be_an(Array)
      expect(result["Knowledge"]).to be_an(Array)
      expect(result["Personal"]).to be_an(Array)
    end

    it "each group contains options" do
      result = helper.item_type_options_for_select(grouped: true)
      result.each do |group_name, options|
        expect(options).not_to be_empty if options.any?
        options.each do |option|
          expect(option).to be_an(Array)
          expect(option.length).to eq(2)
        end
      end
    end

    it "includes task in planning group" do
      result = helper.item_type_options_for_select(grouped: true)
      planning_labels = result["Planning"].map(&:first)
      expect(planning_labels).to include("Task")
    end

    it "includes idea in knowledge group" do
      result = helper.item_type_options_for_select(grouped: true)
      knowledge_labels = result["Knowledge"].map(&:first)
      expect(knowledge_labels).to include("Idea")
    end

    it "includes habit in personal group" do
      result = helper.item_type_options_for_select(grouped: true)
      personal_labels = result["Personal"].map(&:first)
      expect(personal_labels).to include("Habit")
    end
  end

  describe "#item_type_options_with_icons" do
    it "returns array of option hashes" do
      result = helper.item_type_options_with_icons
      expect(result).to be_an(Array)
      expect(result).not_to be_empty
    end

    it "includes required keys in each option" do
      result = helper.item_type_options_with_icons
      result.each do |option|
        expect(option).to have_key(:value)
        expect(option).to have_key(:label)
        expect(option).to have_key(:description)
        expect(option).to have_key(:icon_path)
        expect(option).to have_key(:color)
        expect(option).to have_key(:category)
      end
    end

    it "sets value to string representation of type" do
      result = helper.item_type_options_with_icons
      result.each do |option|
        expect(option[:value]).to be_a(String)
      end
    end

    it "includes icon paths" do
      result = helper.item_type_options_with_icons
      result.each do |option|
        expect(option[:icon_path]).not_to be_empty
      end
    end

    it "includes color classes" do
      result = helper.item_type_options_with_icons
      result.each do |option|
        expect(option[:color]).to include("text-")
      end
    end
  end

  describe "#planning_item_types" do
    it "returns array of planning types" do
      result = helper.planning_item_types
      expect(result).to be_an(Array)
      expect(result).not_to be_empty
    end

    it "includes task in planning types" do
      result = helper.planning_item_types
      expect(result).to include(:task)
    end

    it "all returned types are planning category" do
      result = helper.planning_item_types
      result.each do |type|
        category = helper.item_type_category(type)
        expect(category).to eq(:planning)
      end
    end

    it "does not include knowledge types" do
      result = helper.planning_item_types
      expect(result).not_to include(:idea)
      expect(result).not_to include(:note)
    end

    it "does not include personal types" do
      result = helper.planning_item_types
      expect(result).not_to include(:habit)
    end
  end

  describe "#knowledge_item_types" do
    it "returns array of knowledge types" do
      result = helper.knowledge_item_types
      expect(result).to be_an(Array)
      expect(result).not_to be_empty
    end

    it "includes idea in knowledge types" do
      result = helper.knowledge_item_types
      expect(result).to include(:idea)
    end

    it "includes note in knowledge types" do
      result = helper.knowledge_item_types
      expect(result).to include(:note)
    end

    it "all returned types are knowledge category" do
      result = helper.knowledge_item_types
      result.each do |type|
        category = helper.item_type_category(type)
        expect(category).to eq(:knowledge)
      end
    end

    it "does not include planning types" do
      result = helper.knowledge_item_types
      expect(result).not_to include(:task)
    end

    it "does not include personal types" do
      result = helper.knowledge_item_types
      expect(result).not_to include(:habit)
    end
  end

  describe "#personal_item_types" do
    it "returns array of personal types" do
      result = helper.personal_item_types
      expect(result).to be_an(Array)
      expect(result).not_to be_empty
    end

    it "includes habit in personal types" do
      result = helper.personal_item_types
      expect(result).to include(:habit)
    end

    it "all returned types are personal category" do
      result = helper.personal_item_types
      result.each do |type|
        category = helper.item_type_category(type)
        expect(category).to eq(:personal)
      end
    end

    it "does not include planning types" do
      result = helper.personal_item_types
      expect(result).not_to include(:task)
    end

    it "does not include knowledge types" do
      result = helper.personal_item_types
      expect(result).not_to include(:idea)
      expect(result).not_to include(:note)
    end
  end
end
