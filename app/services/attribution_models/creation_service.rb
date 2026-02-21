# frozen_string_literal: true

module AttributionModels
  class CreationService < ApplicationService
    def initialize(account, params)
      @account = account
      @params = params
    end

    private

    attr_reader :account, :params

    def run
      return error_result([ limit_error ]) unless can_create?
      return error_result(validation_errors) unless valid_code?

      model.save ? success_result(model: model) : error_result(model.errors.full_messages)
    end

    def can_create?
      account.can_create_custom_model?
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

    def model
      @model ||= account.attribution_models.build(permitted_params.merge(model_type: :custom))
    end

    def permitted_params
      params.slice(:name, :dsl_code, :lookback_days)
    end

    def dsl_code
      params[:dsl_code]
    end

    def limit_error
      account.can_edit_full_aml? ? "Custom model limit reached" : "Upgrade to create custom models"
    end
  end
end
