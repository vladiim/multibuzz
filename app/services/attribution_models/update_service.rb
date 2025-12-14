# frozen_string_literal: true

module AttributionModels
  class UpdateService < ApplicationService
    def initialize(model, params, can_edit_code:)
      @model = model
      @params = params
      @can_edit_code = can_edit_code
    end

    private

    attr_reader :model, :params, :can_edit_code

    def run
      return error_result(["Upgrade to edit code"]) unless can_update?
      return error_result(validation_errors) unless valid_code?

      model.update(permitted_params) ? success_result(model: model) : error_result(model.errors.full_messages)
    end

    def can_update?
      can_edit_code || params[:dsl_code].blank?
    end

    def valid_code?
      return true if dsl_code.blank?

      validation_result[:valid]
    end

    def validation_result
      @validation_result ||= ValidationService.new(dsl_code).call
    end

    def validation_errors
      validation_result[:errors].map { |e| e[:message] }
    end

    def permitted_params
      can_edit_code ? params.slice(:name, :dsl_code, :lookback_days) : params.slice(:lookback_days)
    end

    def dsl_code
      params[:dsl_code]
    end
  end
end
