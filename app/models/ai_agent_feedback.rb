# == Schema Information
#
# Table name: ai_agent_feedbacks
#
#  id                  :uuid             not null, primary key
#  comment             :text
#  feedback_type       :integer
#  helpfulness_score   :integer
#  rating              :integer          not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  ai_agent_id         :uuid             not null
#  ai_agent_run_id     :uuid             not null
#  user_id             :uuid             not null
#
# Indexes
#
#  index_ai_agent_feedbacks_on_ai_agent_id        (ai_agent_id)
#  index_ai_agent_feedbacks_on_rating             (rating)
#  index_ai_agent_feedbacks_on_user_id            (user_id,created_at)
#  index_ai_agent_feedbacks_on_ai_agent_run_id    (ai_agent_run_id)
#  index_ai_agent_feedbacks_on_ai_agent_run_id_and_user_id (ai_agent_run_id,user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_9i0j1k2l3m  (ai_agent_id => ai_agents.id)
#  fk_rails_0j1k2l3m4n  (ai_agent_run_id => ai_agent_runs.id)
#  fk_rails_1k2l3m4n5o  (user_id => users.id)
#

class AiAgentFeedback < ApplicationRecord
  belongs_to :ai_agent_run
  belongs_to :ai_agent
  belongs_to :user

  enum :rating, { helpful: 1, neutral: 2, unhelpful: 3, harmful: 4 }
  enum :feedback_type, { accuracy: 0, relevance: 1, speed: 2, quality: 3 }, prefix: true

  validates :rating, presence: true
  validates :user_id, uniqueness: { scope: :ai_agent_run_id, message: "can only rate a run once" }

  scope :recent,     -> { order(created_at: :desc) }
  scope :helpful,    -> { where(rating: :helpful) }
  scope :unhelpful,  -> { where(rating: :unhelpful) }

  after_create :update_agent_average_rating

  private

  def update_agent_average_rating
    agent = ai_agent_run.ai_agent
    feedbacks = AiAgentFeedback.joins(:ai_agent_run)
                               .where(ai_agent_runs: { ai_agent_id: agent.id })
    rating_sum = feedbacks.sum(:rating)
    rating_count = feedbacks.count
    avg = rating_count > 0 ? (rating_sum.to_f / rating_count) : nil
    agent.update_column(:average_rating, avg)
  end
end
