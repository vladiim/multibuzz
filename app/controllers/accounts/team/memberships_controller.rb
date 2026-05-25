# frozen_string_literal: true

module Accounts
  module Team
    class MembershipsController < Accounts::BaseController
      before_action :require_admin

      ERROR_HANDLERS = {
        forbidden: ->(controller, _) { controller.send(:render_forbidden) },
        validation: ->(controller, result) { controller.send(:render_unprocessable, result[:errors].first) },
        not_found: ->(controller, _) { controller.send(:render_unprocessable, "Membership not found") }
      }.freeze

      def update
        role_change_result[:success] ? redirect_with_notice("Role updated successfully") : handle_error(role_change_result)
      end

      def destroy
        removal_result[:success] ? redirect_with_notice("Member removed successfully") : handle_error(removal_result)
      end

      private

      def handle_error(result)
        ERROR_HANDLERS.fetch(result[:error_code], ERROR_HANDLERS[:validation]).call(self, result)
      end

      def role_change_result
        @role_change_result ||= role_change_service.call
      end

      def role_change_service
        @role_change_service ||= ::Team::RoleChangeService.new(
          actor: current_user,
          membership: target_membership,
          new_role: params[:role]
        )
      end

      def removal_result
        @removal_result ||= removal_service.call
      end

      def removal_service
        @removal_service ||= ::Team::RemovalService.new(
          actor: current_user,
          membership: target_membership
        )
      end

      def target_membership
        @target_membership ||= current_account.account_memberships.find_by_prefix_id(params[:id])
      end

      def redirect_with_notice(message)
        redirect_to account_team_path, notice: message
      end

      def render_forbidden
        head :forbidden
      end

      def render_unprocessable(message)
        @memberships = team_memberships
        @can_manage = current_user.admin_of?(current_account)
        @is_owner = current_user.owner_of?(current_account)
        flash.now[:alert] = message
        render "accounts/team/show", status: :unprocessable_entity
      end

      def team_memberships
        current_account
          .account_memberships
          .not_deleted
          .includes(:user)
          .order(role: :desc, created_at: :asc)
      end

      def require_admin
        head :forbidden unless current_user.admin_of?(current_account)
      end
    end
  end
end
