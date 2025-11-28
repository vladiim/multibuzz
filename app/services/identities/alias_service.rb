module Identities
  class AliasService < ApplicationService
    def initialize(account, params, is_test: false)
      @account = account
      @visitor_id = params[:visitor_id]
      @user_id = params[:user_id]
      @is_test = is_test
    end

    private

    attr_reader :account, :visitor_id, :user_id, :is_test

    def run
      return error_result(validation_errors) if invalid?

      visitor.update!(identity: identity)

      success_result
    end

    def invalid?
      validation_errors.any?
    end

    def validation_errors
      @validation_errors ||= [
        ("visitor_id is required" unless visitor_id.present?),
        ("user_id is required" unless user_id.present?),
        ("Visitor not found" if visitor_id.present? && !visitor),
        ("Identity not found" if user_id.present? && !identity)
      ].compact
    end

    def visitor
      @visitor ||= visitor_scope.find_by(visitor_id: visitor_id)
    end

    def identity
      @identity ||= identity_scope.find_by(external_id: user_id)
    end

    def visitor_scope
      is_test ? account.visitors.unscope(where: :is_test) : account.visitors
    end

    def identity_scope
      is_test ? account.identities.unscope(where: :is_test) : account.identities
    end
  end
end
