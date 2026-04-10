# frozen_string_literal: true

module Accounts
  module Team
    class InvitationsController < Accounts::BaseController
      skip_marketing_analytics
      before_action :require_admin

      def create
        params[:resend].present? ? resend_invitation : send_new_invitation
      end

      def destroy
        cancel_pending_invitation || redirect_with_alert("Cannot cancel an accepted membership")
      end

      private

      def resend_invitation
        invitation_result[:success] ? invitation_succeeded("Invitation resent to #{resend_target.user.email}") : redirect_with_alert(invitation_result[:errors].first)
      end

      def send_new_invitation
        invitation_result[:success] ? invitation_succeeded("Invitation sent to #{params[:email]}") : redirect_with_alert(invitation_result[:errors].first)
      end

      def invitation_result
        @invitation_result ||= invitation_service.call
      end

      def invitation_service
        @invitation_service ||= ::Team::InvitationService.new(
          account: current_account,
          inviter: current_user,
          email: params[:email],
          role: params[:role],
          resend_membership: resend_target
        )
      end

      def invitation_succeeded(message)
        TeamMailer.invitation(membership: invitation_result[:membership], token: invitation_result[:invitation_token]).deliver_later
        redirect_to account_team_path, notice: message
      end

      def cancel_pending_invitation
        return unless pending_invitation

        pending_invitation.destroy!
        redirect_to account_team_path, notice: "Invitation cancelled"
      end

      def resend_target
        @resend_target ||= params[:resend].present? ? current_account.account_memberships.find_by_prefix_id(params[:resend]) : nil
      end

      def pending_invitation
        @pending_invitation ||= current_account.account_memberships.pending.find_by_prefix_id(params[:id])
      end

      def redirect_with_alert(message)
        redirect_to account_team_path, alert: message
      end

      def require_admin
        head :forbidden unless current_user.admin_of?(current_account)
      end
    end
  end
end
