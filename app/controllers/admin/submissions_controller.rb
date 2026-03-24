# frozen_string_literal: true

module Admin
  class SubmissionsController < BaseController
    include Pagination

    per_page 25

    def index
      @type_filter = params[:type]
      @submissions = paginate(filtered_submissions)
    end

    def show
      @submission = FormSubmission.find_by_prefix_id!(params[:id])
    end

    private

    def filtered_submissions
      scope = FormSubmission.order(created_at: :desc)
      return scope unless @type_filter.present?

      scope.where(type: @type_filter)
    end
  end
end
