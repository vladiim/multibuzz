# frozen_string_literal: true

module Score
  class AssessmentsController < ApplicationController
    layout "score", only: [ :show ]
    skip_forgery_protection only: [ :create, :claim ]

    RATE_LIMIT = 5
    RATE_WINDOW = 1.hour
    MIN_ELAPSED_MS = 10_000

    def show
    end

    def create
      return head :too_many_requests if rate_limited?
      return head :unprocessable_entity if honeypot_filled?
      return head :unprocessable_entity if too_fast?

      assessment = ScoreAssessment.new(assessment_params)
      assessment.user = current_user if logged_in?

      if assessment.save
        render json: assessment_response(assessment), status: :created
      else
        render json: { errors: assessment.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def claim
      return render json: { error: "Authentication required" }, status: :unauthorized unless logged_in?

      assessment = ScoreAssessment.find_by(claim_token: params[:claim_token])
      return render json: { error: "Assessment not found" }, status: :not_found unless assessment

      assessment.update!(user: current_user, claim_token: nil)
      render json: assessment_response(assessment)
    end

    private

    # Honeypot: bots fill the hidden `website_url` field, humans leave it blank
    def honeypot_filled?
      params[:website_url].present?
    end

    # Timing: assessment takes 2-3 minutes, anything under 10s is a bot
    def too_fast?
      elapsed = params.dig(:assessment, :elapsed_ms).to_i
      elapsed > 0 && elapsed < MIN_ELAPSED_MS
    end

    # Rate limit: 5 assessments per IP per hour
    def rate_limited?
      count = Rails.cache.increment(rate_limit_key, 1, expires_in: RATE_WINDOW)
      count ||= begin
        Rails.cache.write(rate_limit_key, 1, expires_in: RATE_WINDOW)
        1
      end
      count > RATE_LIMIT
    end

    def rate_limit_key
      "score_rate:#{request.remote_ip}"
    end

    def assessment_params
      params.require(:assessment).permit(
        :overall_score, :overall_level, :source,
        dimension_scores: {},
        answers: [ :question_id, :answer_id, :score, :time_ms ],
        context: [ :company_size, :ad_spend, :role, :c1, :c2, :c3 ],
        utm_params: [ :utm_source, :utm_medium, :utm_campaign, :utm_content, :utm_term ]
      )
    end

    def assessment_response(assessment)
      {
        id: assessment.prefix_id,
        overall_score: assessment.overall_score,
        overall_level: assessment.overall_level,
        level_name: assessment.level_name,
        dimension_scores: assessment.dimension_scores,
        strongest_dimension: assessment.strongest_dimension,
        weakest_dimension: assessment.weakest_dimension,
        claim_token: assessment.claim_token,
        claimed: assessment.claimed?
      }
    end
  end
end
