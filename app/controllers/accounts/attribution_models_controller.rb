# frozen_string_literal: true

module Accounts
  class AttributionModelsController < BaseController
    include RequireAdmin

    before_action :set_attribution_model, only: [ :edit, :update, :destroy, :reset, :set_default, :rerun, :test ]

    def index
      @preset_models = current_account.attribution_models.preset
      @custom_models = current_account.attribution_models.custom
      @templates = AML::Templates.all
    end

    def new
      redirect_unless_can_create || (@attribution_model = current_account.attribution_models.build)
    end

    def create
      return redirect_to(account_attribution_models_path, alert: creation_blocked_message) unless current_account.can_create_custom_model?

      result = creation_service.call
      result[:success] ? redirect_to(account_attribution_models_path, notice: t(".success")) : render_new(result)
    end

    def edit
      @effective_code = effective_dsl_code
    end

    def update
      result = update_service.call
      result[:success] ? redirect_to(account_attribution_models_path, notice: t(".success")) : render_edit(result)
    end

    def destroy
      @attribution_model.custom? ? destroy_model : redirect_to(account_attribution_models_path, alert: t(".cannot_delete_preset"))
    end

    def validate
      render json: AttributionModels::ValidationService.new(params[:dsl_code]).call
    end

    def data_readiness
      render json: { models: Attribution::DataReadinessChecker.new(current_account).call }
    end

    def reset
      @attribution_model.update(dsl_code: nil)
      redirect_to edit_account_attribution_model_path(@attribution_model), notice: t(".success")
    end

    def set_default
      current_account.attribution_models.update_all(is_default: false)
      @attribution_model.update(is_default: true)
      redirect_to account_attribution_models_path, notice: t(".success")
    end

    def rerun
      return render_overage_confirmation if rerun_result[:requires_confirmation]
      return redirect_with_rerun_errors unless rerun_result[:success]

      redirect_with_rerun_success
    end

    def test
      @test_result = test_result
    end

    private

    def set_attribution_model
      @attribution_model = current_account.attribution_models.find_by_prefix_id(params[:id])
      head :not_found unless @attribution_model
    end

    def redirect_unless_can_create
      return if current_account.can_create_custom_model?

      redirect_to account_attribution_models_path, alert: creation_blocked_message
    end

    def creation_blocked_message
      current_account.can_edit_full_aml? ? t(".at_limit") : t(".upgrade_required")
    end

    def creation_service
      AttributionModels::CreationService.new(current_account, model_params)
    end

    def update_service
      AttributionModels::UpdateService.new(@attribution_model, model_params, can_edit_code: current_account.can_edit_full_aml?)
    end

    def model_params
      params.require(:attribution_model).permit(:name, :dsl_code, :lookback_days).to_h.symbolize_keys
    end

    def render_new(result)
      @attribution_model = current_account.attribution_models.build(model_params)
      @attribution_model.errors.add(:base, result[:errors].join(", "))
      render :new, status: :unprocessable_entity
    end

    def render_edit(result)
      @effective_code = effective_dsl_code
      @attribution_model.errors.add(:base, result[:errors].join(", "))
      render :edit, status: :unprocessable_entity
    end

    def destroy_model
      @attribution_model.destroy
      redirect_to account_attribution_models_path, notice: t(".success")
    end

    def effective_dsl_code
      @attribution_model.dsl_code.presence || template_code
    end

    def template_code
      return "" unless @attribution_model.preset?

      AML::Templates.generate(@attribution_model.algorithm, lookback_days: @attribution_model.lookback_days)
    end

    def rerun_result
      @rerun_result ||= rerun_initiation_service.call
    end

    def rerun_initiation_service
      Attribution::RerunInitiationService.new(
        attribution_model: @attribution_model,
        confirm_overage: params[:confirm_overage].present?
      )
    end

    def redirect_with_rerun_success
      redirect_to account_attribution_models_path,
        notice: t(".success", count: rerun_result[:rerun_job].total_conversions)
    end

    def redirect_with_rerun_errors
      redirect_to account_attribution_models_path,
        alert: rerun_result[:errors]&.join(", ") || t(".no_stale_conversions")
    end

    def render_overage_confirmation
      @overage = rerun_result[:overage]
      render :rerun_confirmation
    end

    def test_result
      @test_result ||= AttributionModels::TestService.new(
        dsl_code: params[:dsl_code],
        journey_type: params[:journey_type] || :four_touch
      ).call
    end
  end
end
