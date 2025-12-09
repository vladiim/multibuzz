module Accounts
  class ApiKeysController < BaseController
    include RequireAdmin

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

      redirect_to account_api_keys_path, notice: t(".success")
    end

    private

    def generation_result
      @generation_result ||= ApiKeys::GenerationService
        .new(current_account, environment: environment_param, description: api_key_params[:name])
        .call
    end

    def environment_param
      api_key_params[:environment]&.to_sym
    end

    def create_success
      @plaintext_key = generation_result[:plaintext_key]
      @api_key = generation_result[:api_key]
      flash.now[:notice] = t(".success")
      render :show_key
    end

    def create_failure
      flash[:alert] = generation_result[:errors].join(", ")
      redirect_to account_api_keys_path
    end

    def create_missing_environment
      flash[:alert] = t(".missing_environment")
      redirect_to account_api_keys_path
    end

    def api_key_params
      params.require(:api_key).permit(:environment, :name)
    end
  end
end
