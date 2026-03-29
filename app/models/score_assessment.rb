# frozen_string_literal: true

class ScoreAssessment < ApplicationRecord
  belongs_to :user, optional: true
  has_one :score_team_membership, dependent: :destroy
  has_one :score_team, through: :score_team_membership

  has_prefix_id :score

  validates :overall_score, presence: true,
    numericality: { greater_than_or_equal_to: Score::MIN_SCORE, less_than_or_equal_to: Score::MAX_SCORE }
  validates :overall_level, presence: true,
    numericality: { only_integer: true, greater_than_or_equal_to: Score::MIN_LEVEL, less_than_or_equal_to: Score::MAX_LEVEL }

  before_create :generate_claim_token, unless: :user_id?

  def claimed?
    user_id.present?
  end

  def level_name
    Score::LEVEL_NAMES[overall_level]
  end

  def strongest_dimension
    return nil if dimension_scores.blank?

    dimension_scores.max_by { |_, v| v }&.first
  end

  def weakest_dimension
    return nil if dimension_scores.blank?

    dimension_scores.min_by { |_, v| v }&.first
  end

  def dimension_level(dimension)
    score = dimension_scores[dimension.to_s]
    return nil unless score

    Score.level_for_score(score)
  end

  private

  def generate_claim_token
    self.claim_token = SecureRandom.urlsafe_base64(32)
  end
end
