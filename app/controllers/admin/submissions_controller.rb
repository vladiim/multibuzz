# frozen_string_literal: true

module Admin
  class SubmissionsController < BaseController
    include Pagination

    per_page 25

    def index
      @submissions = paginate(FormSubmission.order(created_at: :desc))
    end

    def show
      @submission = FormSubmission.find_by_prefix_id!(params[:id])
    end
  end
end
