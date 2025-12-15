module Api
  module V1
    module Test
      # Test setup endpoint for SDK integration tests
      # Creates and tears down test accounts/API keys
      #
      # ONLY works in test/development environments
      # NO authentication required (bootstrapping credentials)
      class SetupsController < ActionController::API
        before_action :require_test_environment

        # POST /api/v1/test/setup
        # Creates a test account and API key
        # Returns: { account_slug, api_key }
        def create
          account = create_test_account
          result = ApiKeys::GenerationService.new(account, environment: :test).call

          if result[:success]
            render json: {
              success: true,
              account_slug: account.slug,
              api_key: result[:plaintext_key]
            }, status: :created
          else
            account.destroy
            render json: { success: false, errors: result[:errors] }, status: :unprocessable_entity
          end
        end

        # DELETE /api/v1/test/setup
        # Tears down a test account and all its data
        # Params: account_slug (required)
        def destroy
          return render_bad_request("account_slug is required") unless account_slug.present?

          account = Account.find_by(slug: account_slug)
          return render json: { success: true, message: "Account not found" } unless account

          # Only allow deletion of SDK test accounts
          unless account.slug.start_with?("sdk-test-")
            return render json: {
              success: false,
              error: "Can only delete SDK test accounts (slug must start with sdk-test-)"
            }, status: :forbidden
          end

          account.destroy
          render json: { success: true, message: "Test account deleted" }
        end

        private

        def require_test_environment
          return if Rails.env.test? || Rails.env.development?

          render json: {
            error: "This endpoint is only available in test/development environments"
          }, status: :forbidden
        end

        def account_slug
          params[:account_slug]
        end

        def create_test_account
          slug = "sdk-test-#{SecureRandom.hex(8)}"
          Account.create!(
            name: "SDK Test Account",
            slug: slug,
            status: :active
          )
        end

        def render_bad_request(error)
          render json: { error: error }, status: :bad_request
        end
      end
    end
  end
end
