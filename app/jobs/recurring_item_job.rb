class RecurringItemJob < ApplicationJob
  queue_as :default

  def perform
    ListItem.recurring
            .where(status: :completed)
            .where.not(completed_at: nil)
            .find_each do |item|
      Recurring::SpawnNextOccurrenceService.call(item)
    end
  end
end
