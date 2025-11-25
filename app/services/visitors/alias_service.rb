module Visitors
  class AliasService < ApplicationService
    def initialize(account, params)
      @account = account
      @visitor_id = params[:visitor_id]
      @user_id = params[:user_id]
    end

    private

    attr_reader :account, :visitor_id, :user_id

    def run
      return error_result(["visitor_id is required"]) unless visitor_id.present?
      return error_result(["user_id is required"]) unless user_id.present?
      return error_result(["Visitor not found"]) unless visitor

      visitor.update!(user_id: user_id)

      success_result
    end

    def visitor
      @visitor ||= account.visitors.find_by(visitor_id: visitor_id)
    end
  end
end
