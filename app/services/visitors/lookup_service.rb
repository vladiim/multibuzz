module Visitors
  class LookupService
    def initialize(account)
      @account = account
    end

    def call(visitor_id)
      visitor = account.visitors.find_by(visitor_id: visitor_id)
      created = visitor.nil?

      visitor ||= account.visitors.create(visitor_id: visitor_id)

      return error_result(visitor) unless visitor.persisted?

      visitor.touch_last_seen! unless created
      success_result(visitor, created)
    end

    private

    attr_reader :account

    def success_result(visitor, created)
      {
        success: true,
        visitor: visitor,
        created: created
      }
    end

    def error_result(visitor)
      {
        success: false,
        errors: visitor.errors.full_messages
      }
    end
  end
end
