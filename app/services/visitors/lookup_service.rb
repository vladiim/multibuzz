module Visitors
  class LookupService < ApplicationService
    def initialize(account, visitor_id)
      @account = account
      @visitor_id = visitor_id
    end

    private

    attr_reader :account, :visitor_id

    def run
      created = visitor.nil?

      unless visitor
        @visitor = account.visitors.create(visitor_id: visitor_id)
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
