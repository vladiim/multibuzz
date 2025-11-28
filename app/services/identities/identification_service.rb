module Identities
  class IdentificationService < ApplicationService
    def initialize(account, params, is_test: false)
      @account = account
      @user_id = params[:user_id]
      @visitor_id = params[:visitor_id]
      @traits = params[:traits] || {}
      @is_test = is_test
    end

    private

    attr_reader :account, :user_id, :visitor_id, :traits, :is_test

    def run
      return error_result(validation_errors) if invalid?

      persist_identity
      link_visitor_if_present

      success_result
    end

    def invalid?
      validation_errors.any?
    end

    def validation_errors
      @validation_errors ||= [
        ("user_id is required" unless user_id.present?)
      ].compact
    end

    def persist_identity
      identity.traits = traits
      identity.last_identified_at = Time.current
      identity.save!
    end

    def link_visitor_if_present
      return unless visitor_id.present?
      return unless visitor

      visitor.update!(identity: identity)
    end

    def identity
      @identity ||= identity_scope.find_or_initialize_by(external_id: user_id) do |i|
        i.first_identified_at = Time.current
        i.last_identified_at = Time.current
        i.is_test = is_test
      end
    end

    def identity_scope
      is_test ? account.identities.unscope(where: :is_test) : account.identities
    end

    def visitor
      @visitor ||= visitor_scope.find_by(visitor_id: visitor_id)
    end

    def visitor_scope
      is_test ? account.visitors.unscope(where: :is_test) : account.visitors
    end
  end
end
