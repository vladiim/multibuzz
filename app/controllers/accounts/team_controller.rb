# frozen_string_literal: true

module Accounts
  class TeamController < BaseController
    def show
      @memberships = team_memberships
      @can_manage = current_user.admin_of?(current_account)
      @is_owner = current_user.owner_of?(current_account)
    end

    private

    def team_memberships
      current_account
        .account_memberships
        .not_deleted
        .includes(:user)
        .order(role: :desc, created_at: :asc)
    end
  end
end
