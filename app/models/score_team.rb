# frozen_string_literal: true

class ScoreTeam < ApplicationRecord
  belongs_to :created_by, class_name: "User"
  has_many :score_team_memberships, dependent: :destroy
  has_many :users, through: :score_team_memberships
  has_many :score_assessments, through: :score_team_memberships

  has_prefix_id :steam

  validates :invite_slug, presence: true, uniqueness: true

  before_validation :generate_invite_slug, on: :create

  def unlocked?
    member_count >= Score::TEAM_UNLOCK_THRESHOLD
  end

  def recalculate_alignment!
    return unless unlocked?

    result = Score::AlignmentCalculator.new(score_assessments.pluck(:overall_score)).call
    return unless result

    update!(alignment_score: result, member_count: score_assessments.count)
  end

  private

  def generate_invite_slug
    self.invite_slug ||= SecureRandom.urlsafe_base64(8)
  end
end
