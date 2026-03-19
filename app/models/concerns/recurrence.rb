module Recurrence
  extend ActiveSupport::Concern

  RULES = %w[none daily weekly biweekly monthly yearly].freeze

  included do
    validates :recurrence_rule, inclusion: { in: RULES }
    validate :recurrence_end_date_after_due_date, if: -> { recurring? && recurrence_end_date.present? }

    scope :recurring, -> { where.not(recurrence_rule: "none") }
  end

  def recurring?
    recurrence_rule != "none"
  end

  def next_due_date
    return nil unless recurring? && due_date.present?
    case recurrence_rule
    when "daily"    then due_date + 1.day
    when "weekly"   then due_date + 1.week
    when "biweekly" then due_date + 2.weeks
    when "monthly"  then due_date + 1.month
    when "yearly"   then due_date + 1.year
    end
  end

  def within_recurrence_window?
    return true if recurrence_end_date.blank?
    next_due_date.present? && next_due_date <= recurrence_end_date
  end

  private

  def recurrence_end_date_after_due_date
    return unless due_date.present? && recurrence_end_date <= due_date
    errors.add(:recurrence_end_date, "must be after the due date")
  end
end
