# frozen_string_literal: true

module Accounts
  module Team
    class OwnershipController < Accounts::BaseController
      skip_marketing_analytics
      before_action :require_owner

      def transfer
        transfer_result[:success] ? redirect_with_notice : handle_error
      end

      private

      def transfer_result
        @transfer_result ||= transfer_service.call
      end

      def transfer_service
        @transfer_service ||= ::Team::OwnershipTransferService.new(
          actor: current_user,
          account: current_account,
          new_owner_membership: new_owner_membership,
          confirmation: params[:confirmation]
        )
      end

      def new_owner_membership
        @new_owner_membership ||= current_account.account_memberships.find_by_prefix_id(params[:new_owner_id])
      end

      def redirect_with_notice
        redirect_to account_team_path, notice: "Ownership transferred successfully"
      end

      def handle_error
        transfer_result[:error_code] == :forbidden ? head(:forbidden) : render_unprocessable
      end

      def render_unprocessable
        @memberships = team_memberships
        @can_manage = current_user.admin_of?(current_account)
        @is_owner = current_user.owner_of?(current_account)
        flash.now[:alert] = transfer_result[:errors].first
        render "accounts/team/show", status: :unprocessable_entity
      end

      def team_memberships
        current_account
          .account_memberships
          .not_deleted
          .includes(:user)
          .order(role: :desc, created_at: :asc)
      end

      def require_owner
        head :forbidden unless current_user.owner_of?(current_account)
      end
    end
  end
end
