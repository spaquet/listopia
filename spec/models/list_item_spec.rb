# spec/models/list_item_spec.rb
# == Schema Information
#
# Table name: list_items
#
#  id                  :uuid             not null, primary key
#  completed_at        :datetime
#  description         :text
#  due_date            :datetime
#  duration_days       :integer
#  estimated_duration  :decimal(10, 2)   default(0.0), not null
#  item_type           :integer          default("task"), not null
#  metadata            :json
#  position            :integer          default(0)
#  priority            :integer          default("medium"), not null
#  recurrence_end_date :datetime
#  recurrence_rule     :string           default("none"), not null
#  reminder_at         :datetime
#  skip_notifications  :boolean          default(FALSE), not null
#  start_date          :datetime
#  status              :integer          default("pending"), not null
#  status_changed_at   :datetime
#  title               :string           not null
#  total_tracked_time  :decimal(10, 2)   default(0.0), not null
#  url                 :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  assigned_user_id    :uuid
#  board_column_id     :uuid
#  list_id             :uuid             not null
#
# Indexes
#
#  index_list_items_on_assigned_user_id             (assigned_user_id)
#  index_list_items_on_assigned_user_id_and_status  (assigned_user_id,status)
#  index_list_items_on_board_column_id              (board_column_id)
#  index_list_items_on_completed_at                 (completed_at)
#  index_list_items_on_created_at                   (created_at)
#  index_list_items_on_due_date                     (due_date)
#  index_list_items_on_due_date_and_status          (due_date,status)
#  index_list_items_on_item_type                    (item_type)
#  index_list_items_on_list_id                      (list_id)
#  index_list_items_on_list_id_and_position         (list_id,position) UNIQUE
#  index_list_items_on_list_id_and_priority         (list_id,priority)
#  index_list_items_on_list_id_and_status           (list_id,status)
#  index_list_items_on_position                     (position)
#  index_list_items_on_priority                     (priority)
#  index_list_items_on_skip_notifications           (skip_notifications)
#  index_list_items_on_status                       (status)
#
# Foreign Keys
#
#  fk_rails_...  (assigned_user_id => users.id)
#  fk_rails_...  (board_column_id => board_columns.id)
#  fk_rails_...  (list_id => lists.id)
#
require 'rails_helper'

RSpec.describe ListItem, type: :model do
  describe "associations" do
    it { should belong_to(:list) }
    it { should belong_to(:assigned_user).class_name("User").optional }
    it { should belong_to(:board_column).optional }
    it { should have_many(:time_entries).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_most(255) }
    it { should validate_presence_of(:item_type) }
    it { should validate_presence_of(:priority) }
    it { should validate_presence_of(:status) }
    it { should validate_numericality_of(:position).only_integer.is_greater_than_or_equal_to(0) }
  end

  describe "enums" do
    describe "item_type" do
      it "has all item_type values" do
        expected_types = {
          "task" => 0, "milestone" => 1, "feature" => 2, "bug" => 3,
          "decision" => 4, "meeting" => 5, "reminder" => 6, "note" => 7,
          "reference" => 8, "habit" => 9, "health" => 10, "learning" => 11,
          "travel" => 12, "shopping" => 13, "home" => 14, "finance" => 15,
          "social" => 16, "entertainment" => 17
        }
        expect(ListItem.item_types).to eq(expected_types)
      end
    end

    describe "priority" do
      it "has correct priority values" do
        expect(ListItem.priorities).to eq({ "low" => 0, "medium" => 1, "high" => 2, "urgent" => 3 })
      end

      it "provides instance methods for priority" do
        low = create(:list_item, :low_priority)
        high = create(:list_item, :high_priority)
        expect(low.priority_low?).to be true
        expect(high.priority_high?).to be true
      end
    end

    describe "status" do
      it "has correct status values" do
        expect(ListItem.statuses).to eq({ "pending" => 0, "in_progress" => 1, "completed" => 2 })
      end

      it "provides instance methods for status" do
        pending = create(:list_item, :pending)
        completed = create(:list_item, :completed)
        expect(pending.status_pending?).to be true
        expect(completed.status_completed?).to be true
      end
    end
  end

  describe "URL validation" do
    context "with valid HTTP/HTTPS URLs" do
      it "accepts http URLs" do
        item = build(:list_item, url: "http://example.com")
        expect(item).to be_valid
      end

      it "accepts https URLs" do
        item = build(:list_item, url: "https://example.com")
        expect(item).to be_valid
      end

      it "accepts URLs with paths and query parameters" do
        item = build(:list_item, url: "https://example.com/path/to/page?param=value&other=123")
        expect(item).to be_valid
      end

      it "accepts URLs with fragments" do
        item = build(:list_item, url: "https://example.com/page#section")
        expect(item).to be_valid
      end

      it "accepts relative URLs starting with /" do
        item = build(:list_item, url: "/internal/path")
        expect(item).to be_valid
      end
    end

    context "with invalid URLs" do
      it "rejects javascript: URLs" do
        item = build(:list_item, url: "javascript:alert(\"xss\")")
        expect(item).not_to be_valid
        expect(item.errors[:url].join).to match(/must be a valid HTTP\/HTTPS URL|is not a valid URL/)
      end

      it "rejects data: URLs" do
        item = build(:list_item, url: "data:text/html,<script>alert(\"xss\")</script>")
        expect(item).not_to be_valid
        expect(item.errors[:url].join).to match(/must be a valid HTTP\/HTTPS URL|is not a valid URL/)
      end

      it "rejects vbscript: URLs" do
        item = build(:list_item, url: "vbscript:msgbox(\"xss\")")
        expect(item).not_to be_valid
        expect(item.errors[:url].join).to match(/must be a valid HTTP\/HTTPS URL|is not a valid URL/)
      end

      # it "rejects file: URLs" do
      #   item = build(:list_item, url: "file:///etc/passwd")
      #   expect(item).not_to be_valid
      #   expect(item.errors[:url].join).to match(/must be a valid HTTP\/HTTPS URL/)
      # end

      it "rejects malformed URLs" do
        item = build(:list_item, url: "ht!tp://[invalid")
        expect(item).not_to be_valid
        expect(item.errors[:url]).to include("is not a valid URL")
      end
    end

    context "with blank or nil URLs" do
      it "allows blank URLs" do
        item = build(:list_item, url: "")
        expect(item).to be_valid
      end

      it "allows nil URLs" do
        item = build(:list_item, url: nil)
        expect(item).to be_valid
      end
    end
  end

  describe "URL sanitization" do
    context "when saving URLs" do
      it "strips leading and trailing whitespace" do
        item = create(:list_item, url: "  https://example.com  ")
        expect(item.url).to eq("https://example.com")
      end

      it "adds https:// prefix to URLs without scheme" do
        item = create(:list_item, url: "example.com")
        expect(item.url).to eq("https://example.com")
      end

      it "preserves http:// prefix when explicitly provided" do
        item = create(:list_item, url: "http://example.com")
        expect(item.url).to eq("http://example.com")
      end

      it "preserves https:// prefix" do
        item = create(:list_item, url: "https://example.com")
        expect(item.url).to eq("https://example.com")
      end

      it "does not modify relative URLs" do
        item = create(:list_item, url: "/internal/page")
        expect(item.url).to eq("/internal/page")
      end

      it "handles complex URLs correctly" do
        complex_url = "github.com/rails/rails/issues?state=open&label=bug"
        item = create(:list_item, url: complex_url)
        expect(item.url).to eq("https://#{complex_url}")
      end

      it "does not double-prefix https://" do
        item = create(:list_item, url: "https://example.com")
        expect(item.url).not_to eq("https://https://example.com")
      end
    end
  end

  describe "factory validity" do
    it "creates valid default list items" do
      expect(build(:list_item)).to be_valid
    end

    it "creates valid task items" do
      expect(build(:list_item, :task)).to be_valid
    end

    it "creates valid milestone items" do
      expect(build(:list_item, :milestone)).to be_valid
    end

    it "creates valid feature items" do
      expect(build(:list_item, :feature)).to be_valid
    end

    it "creates valid bug items" do
      expect(build(:list_item, :bug)).to be_valid
    end

    it "creates valid decision items" do
      expect(build(:list_item, :decision)).to be_valid
    end

    it "creates valid meeting items" do
      expect(build(:list_item, :meeting)).to be_valid
    end

    it "creates valid reminder items" do
      expect(build(:list_item, :reminder)).to be_valid
    end

    it "creates valid note items" do
      expect(build(:list_item, :note)).to be_valid
    end

    it "creates valid reference items" do
      expect(build(:list_item, :reference)).to be_valid
    end

    it "creates valid habit items" do
      expect(build(:list_item, :habit)).to be_valid
    end

    it "creates valid health items" do
      expect(build(:list_item, :health)).to be_valid
    end

    it "creates valid learning items" do
      expect(build(:list_item, :learning)).to be_valid
    end

    it "creates valid travel items" do
      expect(build(:list_item, :travel)).to be_valid
    end

    it "creates valid shopping items" do
      expect(build(:list_item, :shopping)).to be_valid
    end

    it "creates valid home items" do
      expect(build(:list_item, :home)).to be_valid
    end

    it "creates valid finance items" do
      expect(build(:list_item, :finance)).to be_valid
    end

    it "creates valid social items" do
      expect(build(:list_item, :social)).to be_valid
    end

    it "creates valid entertainment items" do
      expect(build(:list_item, :entertainment)).to be_valid
    end

    it "creates items with all status traits" do
      expect(build(:list_item, :pending)).to be_valid
      expect(build(:list_item, :in_progress)).to be_valid
      expect(build(:list_item, :completed)).to be_valid
    end

    it "creates items with all priority traits" do
      expect(build(:list_item, :low_priority)).to be_valid
      expect(build(:list_item, :high_priority)).to be_valid
      expect(build(:list_item, :urgent_priority)).to be_valid
    end

    it "creates items with due dates" do
      expect(build(:list_item, :with_due_date)).to be_valid
      expect(build(:list_item, :overdue)).to be_valid
      expect(build(:list_item, :due_soon)).to be_valid
    end

    it "creates assigned items" do
      expect(build(:list_item, :assigned)).to be_valid
    end

    it "creates recurring items" do
      expect(build(:list_item, :daily_recurring)).to be_valid
      expect(build(:list_item, :weekly_recurring)).to be_valid
    end

    it "creates items with time tracked" do
      item = build(:list_item, :with_time_logged)
      expect(item).to be_valid
      expect(item.total_tracked_time).to eq(5.5)
      expect(item.estimated_duration).to eq(8.0)
    end

    it "creates items with metadata" do
      item = build(:list_item, :with_metadata)
      expect(item).to be_valid
      expect(item.metadata).to eq({ "custom_field" => "value", "tags" => [ "important", "bug" ] })
    end

    it "creates complex combined trait items" do
      expect(build(:list_item, :urgent_overdue_task)).to be_valid
      expect(build(:list_item, :completed_with_time_tracked)).to be_valid
      expect(build(:list_item, :assigned_high_priority_due_soon)).to be_valid
    end
  end

  describe "factory default values" do
    let(:item) { create(:list_item) }

    it "sets correct defaults" do
      expect(item.item_type).to eq("task")
      expect(item.priority).to eq("medium")
      expect(item.status).to eq("pending")
      expect(item.position).to be_a(Integer)
      expect(item.position).to be >= 0
      expect(item.duration_days).to eq(0)
      expect(item.estimated_duration).to eq(0.0)
      expect(item.total_tracked_time).to eq(0.0)
      expect(item.recurrence_rule).to eq("none")
      expect(item.skip_notifications).to be false
    end

    it "sets list association" do
      expect(item.list).to be_present
      expect(item.list).to be_a(List)
    end

    it "generates unique sequence titles" do
      item1 = create(:list_item)
      item2 = create(:list_item)
      expect(item1.title).not_to eq(item2.title)
    end

    it "generates faker description" do
      expect(item.description).not_to be_blank
    end
  end

  describe "trait behavior" do
    describe "work and project item types" do
      it "creates tasks" do
        task = create(:list_item, :task)
        expect(task.item_type).to eq("task")
      end

      it "creates milestones" do
        milestone = create(:list_item, :milestone)
        expect(milestone.item_type).to eq("milestone")
      end

      it "creates features" do
        feature = create(:list_item, :feature)
        expect(feature.item_type).to eq("feature")
      end

      it "creates bugs" do
        bug = create(:list_item, :bug)
        expect(bug.item_type).to eq("bug")
      end

      it "creates decisions" do
        decision = create(:list_item, :decision)
        expect(decision.item_type).to eq("decision")
      end

      it "creates meetings" do
        meeting = create(:list_item, :meeting)
        expect(meeting.item_type).to eq("meeting")
      end

      it "creates reminders with reminder_at" do
        reminder = create(:list_item, :reminder)
        expect(reminder.item_type).to eq("reminder")
        expect(reminder.reminder_at).to be_present
      end

      it "creates notes" do
        note = create(:list_item, :note)
        expect(note.item_type).to eq("note")
      end

      it "creates references with url" do
        reference = create(:list_item, :reference)
        expect(reference.item_type).to eq("reference")
        expect(reference.url).to be_present
      end
    end

    describe "personal life item types" do
      it "creates habits" do
        habit = create(:list_item, :habit)
        expect(habit.item_type).to eq("habit")
      end

      it "creates health items" do
        health = create(:list_item, :health)
        expect(health.item_type).to eq("health")
      end

      it "creates learning items" do
        learning = create(:list_item, :learning)
        expect(learning.item_type).to eq("learning")
      end

      it "creates travel items" do
        travel = create(:list_item, :travel)
        expect(travel.item_type).to eq("travel")
      end

      it "creates shopping items" do
        shopping = create(:list_item, :shopping)
        expect(shopping.item_type).to eq("shopping")
      end

      it "creates home items" do
        home = create(:list_item, :home)
        expect(home.item_type).to eq("home")
      end

      it "creates finance items" do
        finance = create(:list_item, :finance)
        expect(finance.item_type).to eq("finance")
      end

      it "creates social items" do
        social = create(:list_item, :social)
        expect(social.item_type).to eq("social")
      end

      it "creates entertainment items" do
        entertainment = create(:list_item, :entertainment)
        expect(entertainment.item_type).to eq("entertainment")
      end
    end

    describe "status traits" do
      it "creates pending items without status_changed_at" do
        item = create(:list_item, :pending)
        expect(item.status).to eq("pending")
        expect(item.status_changed_at).to be_nil
      end

      it "creates in-progress items with status_changed_at" do
        item = create(:list_item, :in_progress)
        expect(item.status).to eq("in_progress")
        expect(item.status_changed_at).to be_present
      end

      it "creates completed items with status_changed_at" do
        item = create(:list_item, :completed)
        expect(item.status).to eq("completed")
        expect(item.status_changed_at).to be_present
      end
    end

    describe "priority traits" do
      it "creates low priority items" do
        item = create(:list_item, :low_priority)
        expect(item.priority).to eq("low")
        expect(item.priority_low?).to be true
      end

      it "creates high priority items" do
        item = create(:list_item, :high_priority)
        expect(item.priority).to eq("high")
        expect(item.priority_high?).to be true
      end

      it "creates urgent priority items" do
        item = create(:list_item, :urgent_priority)
        expect(item.priority).to eq("urgent")
        expect(item.priority_urgent?).to be true
      end
    end

    describe "due date traits" do
      it "creates items with due date in future" do
        item = create(:list_item, :with_due_date)
        expect(item.due_date).to be > Time.current
      end

      it "creates overdue items" do
        item = create(:list_item, :overdue)
        expect(item.due_date).to be < Time.current
        expect(item.status).to eq("pending")
      end

      it "creates items due soon" do
        item = create(:list_item, :due_soon)
        expect(item.due_date).to be_within(3.days).of(Time.current)
      end
    end

    describe "assignment traits" do
      it "creates unassigned items" do
        item = create(:list_item)
        expect(item.assigned_user).to be_nil
      end

      it "creates assigned items" do
        item = create(:list_item, :assigned)
        expect(item.assigned_user).to be_present
        expect(item.assigned_user).to be_a(User)
      end

      it "creates items assigned to specific user" do
        user = create(:user)
        item = create(:list_item, :assigned_to, assigned_user: user)
        expect(item.assigned_user).to eq(user)
      end
    end

    describe "recurrence traits" do
      it "creates daily recurring items" do
        item = create(:list_item, :daily_recurring)
        expect(item.recurrence_rule).to eq("daily")
        expect(item.recurrence_end_date).to be_present
      end

      it "creates weekly recurring items" do
        item = create(:list_item, :weekly_recurring)
        expect(item.recurrence_rule).to eq("weekly")
        expect(item.recurrence_end_date).to be_present
      end
    end

    describe "tracking traits" do
      it "creates items with time logged" do
        item = create(:list_item, :with_time_logged)
        expect(item.total_tracked_time).to eq(5.5)
        expect(item.estimated_duration).to eq(8.0)
      end
    end

    describe "complex combined traits" do
      it "creates urgent overdue tasks" do
        item = create(:list_item, :urgent_overdue_task)
        expect(item.priority).to eq("urgent")
        expect(item.status).to eq("pending")
        expect(item.due_date).to be < Time.current
      end

      it "creates completed items with time tracked" do
        item = create(:list_item, :completed_with_time_tracked)
        expect(item.status).to eq("completed")
        expect(item.total_tracked_time).to eq(8.0)
        expect(item.status_changed_at).to be_present
      end

      it "creates assigned high priority items due soon" do
        item = create(:list_item, :assigned_high_priority_due_soon)
        expect(item.assigned_user).to be_present
        expect(item.priority).to eq("high")
        expect(item.due_date).to be_within(3.days).of(Time.current)
        expect(item.status).to eq("in_progress")
      end
    end
  end

  describe "list association" do
    let(:list) { create(:list) }
    let(:item) { create(:list_item, list: list) }

    it "belongs to a list" do
      expect(item.list).to eq(list)
    end

    it "is destroyed when list is destroyed" do
      item_id = item.id
      expect { list.destroy }.to change(ListItem, :count).by(-1)
      expect(ListItem.exists?(item_id)).to be false
    end
  end

  describe "assigned user association" do
    let(:user) { create(:user) }
    let(:item) { create(:list_item, assigned_user: user) }

    it "can be assigned to a user" do
      expect(item.assigned_user).to eq(user)
    end

    it "is optional" do
      item_without_assignment = build(:list_item, assigned_user: nil)
      expect(item_without_assignment).to be_valid
    end
  end

  describe "schema attributes" do
    let(:item) { build(:list_item) }

    it "has required string attributes" do
      expect(item).to respond_to(:title)
      expect(item).to respond_to(:description)
      expect(item).to respond_to(:url)
      expect(item).to respond_to(:recurrence_rule)
    end

    it "has required integer attributes" do
      expect(item).to respond_to(:position)
      expect(item).to respond_to(:duration_days)
    end

    it "has required decimal attributes" do
      expect(item).to respond_to(:estimated_duration)
      expect(item).to respond_to(:total_tracked_time)
    end

    it "has required datetime attributes" do
      expect(item).to respond_to(:start_date)
      expect(item).to respond_to(:due_date)
      expect(item).to respond_to(:status_changed_at)
      expect(item).to respond_to(:reminder_at)
      expect(item).to respond_to(:recurrence_end_date)
    end

    it "has required boolean attributes" do
      expect(item).to respond_to(:skip_notifications)
    end

    it "has required json attribute" do
      expect(item).to respond_to(:metadata)
    end
  end

  describe "unique constraint on list_id and position" do
    let(:list) { create(:list) }
    let!(:item1) { create(:list_item, list: list, position: 0) }

    it "allows same position in different lists" do
      list2 = create(:list)
      item2 = create(:list_item, list: list2, position: 0)
      expect(item2.position).to eq(item1.position)
      expect(item2.list_id).not_to eq(item1.list_id)
    end
  end

  describe "logidze auditing" do
    let(:item) { create(:list_item) }

    it "includes logidze for change tracking" do
      expect(item).to respond_to(:log_data)
    end
  end

  describe "turbo broadcasting" do
    it "includes Turbo::Broadcastable" do
      expect(ListItem.included_modules).to include(Turbo::Broadcastable)
    end
  end

  describe "model methods" do
    describe "#overdue?" do
      it "returns true for overdue pending items" do
        item = create(:list_item, :overdue)
        expect(item.overdue?).to be true
      end

      it "returns false for completed items" do
        item = create(:list_item, :completed, due_date: 3.days.ago)
        expect(item.overdue?).to be false
      end

      it "returns false for items without due date" do
        item = create(:list_item)
        expect(item.overdue?).to be false
      end

      it "returns false for future due dates" do
        item = create(:list_item, :with_due_date)
        expect(item.overdue?).to be false
      end
    end

    describe "#toggle_completion!" do
      it "toggles from pending to completed" do
        item = create(:list_item, :pending)
        item.toggle_completion!
        expect(item.status).to eq("completed")
      end

      it "toggles from completed to pending" do
        item = create(:list_item, :completed)
        item.toggle_completion!
        expect(item.status).to eq("pending")
      end

      it "sets status_changed_at when toggled" do
        item = create(:list_item, :pending)
        item.toggle_completion!
        expect(item.status_changed_at).to be_present
      end
    end

    describe "#editable_by?" do
      let(:owner) { create(:user) }
      let(:collaborator) { create(:user) }
      let(:other_user) { create(:user) }
      let(:list) { create(:list, owner: owner) }
      let(:item) { create(:list_item, list: list) }

      it "is editable by list owner" do
        expect(item.editable_by?(owner)).to be true
      end

      it "is editable by assigned user" do
        item.update(assigned_user: other_user)
        expect(item.editable_by?(other_user)).to be true
      end

      it "is not editable by unrelated user" do
        expect(item.editable_by?(other_user)).to be false
      end

      it "is not editable by nil user" do
        expect(item.editable_by?(nil)).to be false
      end
    end
  end
end
