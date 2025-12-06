module Visitors
  class LookupService < ApplicationService
    def initialize(account, visitor_id, is_test: false)
      @account = account
      @visitor_id = visitor_id
      @is_test = is_test
    end

    private

    attr_reader :account, :visitor_id, :is_test

    def run
      created = visitor.nil?

      unless visitor
        @visitor = account.visitors.create(visitor_id: visitor_id, is_test: is_test)
        return error_result(visitor.errors.full_messages) unless visitor.persisted?
        created = true
      end

      visitor.touch_last_seen! unless created

      success_result(visitor: visitor, created: created)
    end

    def visitor
      @visitor ||= account.visitors.find_by(visitor_id: visitor_id)
    end
  end
end
