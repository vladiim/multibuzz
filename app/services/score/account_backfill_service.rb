# frozen_string_literal: true

module Score
  # Backfills score_assessments.account_id for assessments claimed before the
  # account_id column existed. Only assigns when the assessment's user has
  # exactly one active membership. Multi-membership users are skipped (no
  # tiebreaker) so we never guess which account the score belongs to.
  class AccountBackfillService < ApplicationService
    ASSIGNED                     = :assigned
    SKIPPED_NO_ACTIVE_MEMBERSHIP = :skipped_no_active_membership
    SKIPPED_MULTI_MEMBERSHIP     = :skipped_multi_membership

    OUTCOMES = [ ASSIGNED, SKIPPED_NO_ACTIVE_MEMBERSHIP, SKIPPED_MULTI_MEMBERSHIP ].freeze

    private

    def run
      success_result(zero_counts.merge(tallies))
    end

    def tallies
      @tallies ||= candidates.find_each.map { |assessment| Candidate.new(assessment).outcome }.tally
    end

    def candidates
      ScoreAssessment.where.not(user_id: nil).where(account_id: nil)
    end

    def zero_counts
      OUTCOMES.index_with { 0 }
    end

    # Encapsulates the "what should happen to this one assessment" decision so
    # the service body stays a pure transformation (candidates → tallies).
    class Candidate
      def initialize(assessment)
        @assessment = assessment
      end

      def outcome
        return assign_to_sole_account! if memberships.one?
        return SKIPPED_NO_ACTIVE_MEMBERSHIP if memberships.none?
        SKIPPED_MULTI_MEMBERSHIP
      end

      private

      attr_reader :assessment

      def assign_to_sole_account!
        assessment.update!(account: memberships.first.account)
        ASSIGNED
      end

      def memberships = @memberships ||= assessment.user.active_memberships.to_a
    end
  end
end
