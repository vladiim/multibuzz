# frozen_string_literal: true

module Admin
  class FeatureFlagsController < BaseController
    def index
      @flag_summaries = flag_summaries
      @accounts_with_flags = accounts_with_flags
    end

    def create
      return reject_unknown_flag unless valid_flag?

      target_account.enable_feature!(flag_name)
      redirect_to admin_feature_flags_path, notice: "Enabled #{flag_name} for #{target_account.name}."
    end

    def destroy
      return reject_unknown_flag unless valid_flag?

      target_account.disable_feature!(flag_name)
      redirect_to admin_feature_flags_path, notice: "Disabled #{flag_name} for #{target_account.name}."
    end

    private

    def target_account
      @target_account ||= Account.find(params[:account_id])
    end

    def flag_name
      params[:flag_name].to_s
    end

    def valid_flag?
      FeatureFlags::ALL.include?(flag_name)
    end

    def reject_unknown_flag
      redirect_to admin_feature_flags_path, alert: "Unknown flag: #{flag_name}"
    end

    def flag_summaries
      FeatureFlags::ALL.map { |name| [ name, AccountFeatureFlag.where(flag_name: name).count ] }
    end

    def accounts_with_flags
      Account
        .joins(:feature_flags)
        .distinct
        .order(:name)
        .includes(:feature_flags)
    end
  end
end
