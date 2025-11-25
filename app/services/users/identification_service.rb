module Users
  class IdentificationService < ApplicationService
    def initialize(account, params)
      @account = account
      @user_id = params[:user_id]
      @visitor_id = params[:visitor_id]
      @traits = params[:traits] || {}
    end

    private

    attr_reader :account, :user_id, :visitor_id, :traits

    def run
      return error_result(["user_id is required"]) unless user_id.present?

      persist_identification
      link_visitor_if_present

      success_result
    end

    def persist_identification
      user.traits = traits
      user.last_identified_at = Time.current
      user.save!
    end

    def link_visitor_if_present
      return unless visitor_id.present?
      return unless visitor

      visitor.update!(user_id: user_id)
    end

    def user
      @user ||= account.users.find_or_initialize_by(external_id: user_id)
    end

    def visitor
      @visitor ||= account.visitors.find_by(visitor_id: visitor_id)
    end
  end
end
