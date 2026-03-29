# frozen_string_literal: true

module Score
  class AssessmentsController < ApplicationController
    layout "score", only: [ :show ]
    skip_forgery_protection only: [ :create, :claim ]

    def show
    end

    def create
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

    def assessment_params
      params.require(:assessment).permit(
        :overall_score, :overall_level, :source,
        dimension_scores: {},
        answers: [ :question_id, :answer_id, :score, :time_ms ],
        context: [ :company_size, :ad_spend, :role ],
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
