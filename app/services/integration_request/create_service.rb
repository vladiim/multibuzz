# frozen_string_literal: true

module IntegrationRequest
  class CreateService < ApplicationService
    def initialize(user:, account:, params:, request:)
      @user = user
      @account = account
      @params = params
      @ip_address = anonymize_ip(request.remote_ip)
      @user_agent = request.user_agent
    end

    private

    attr_reader :user, :account, :params, :ip_address, :user_agent

    def run
      return error_result([ "You've already requested this platform!" ]) if already_requested?

      submission.save!
      success_result(submission: submission)
    end

    def already_requested?
      return false unless params[:platform_name].present?

      IntegrationRequestSubmission
        .where(email: user.email)
        .where("data->>'platform_name' = ?", params[:platform_name])
        .exists?
    end

    def submission
      @submission ||= IntegrationRequestSubmission.new(
        email: user.email,
        platform_name: params[:platform_name],
        platform_name_other: params[:platform_name_other],
        monthly_spend: params[:monthly_spend],
        notes: params[:notes],
        account_id: account.prefix_id,
        plan_name: account.plan&.name,
        ip_address: ip_address,
        user_agent: user_agent
      )
    end

    def anonymize_ip(ip)
      IPAddr.new(ip).mask(24).to_s
    rescue IPAddr::InvalidAddressError
      nil
    end
  end
end
