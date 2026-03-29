# frozen_string_literal: true

class ScoreTeamMembership < ApplicationRecord
  belongs_to :score_team
  belongs_to :user
  belongs_to :score_assessment

  validates :user_id, uniqueness: { scope: :score_team_id }
  validates :joined_at, presence: true
end
