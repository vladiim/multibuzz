module Dashboard
  class ApiKeysController < ApplicationController
    before_action :require_login

    def index
      @api_keys = current_account.api_keys.order(created_at: :desc)
    end

    def create
      return create_missing_environment unless environment_param

      generation_result[:success] ? create_success : create_failure
    end

    def destroy
      api_key = current_account.api_keys.find(params[:id])
      api_key.revoke!

      redirect_to dashboard_api_keys_path, notice: t("dashboard.api_keys.destroy.success")
    end

    private

    def current_account
      @current_account ||= current_user.primary_account
    end

    def generation_result
      @generation_result ||= ApiKeys::GenerationService
        .new(current_account, environment_param)
        .call(description: api_key_params[:name])
    end

    def environment_param
      api_key_params[:environment]&.to_sym
    end

    def create_success
      @plaintext_key = generation_result[:plaintext_key]
      @api_key = generation_result[:api_key]
      flash.now[:notice] = t("dashboard.api_keys.create.success")
      render :show_key
    end

    def create_failure
      flash.now[:alert] = generation_result[:errors].join(", ")
      @api_keys = current_account.api_keys.order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end

    def create_missing_environment
      flash.now[:alert] = t("dashboard.api_keys.create.missing_environment")
      @api_keys = current_account.api_keys.order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end

    def api_key_params
      params.require(:api_key).permit(:environment, :name)
    end
  end
end
