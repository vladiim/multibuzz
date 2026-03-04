# frozen_string_literal: true

module Dashboard
  class IdentityDetailQuery
    def initialize(account)
      @account = account
    end

    def call(prefix_id)
      find_identity(prefix_id)
        &.tap { |identity| attach_computed_fields(identity) }
    end

    private

    attr_reader :account

    def find_identity(prefix_id)
      account.identities
        .includes(:visitors, :conversions)
        .find_by_prefix_id(prefix_id)
    end

    def attach_computed_fields(identity)
      breakdown = compute_channel_breakdown(identity)
      revenue = compute_total_revenue(identity)

      identity.define_singleton_method(:channel_breakdown) { breakdown }
      identity.define_singleton_method(:total_revenue) { revenue }
    end

    def compute_channel_breakdown(identity)
      visitor_ids = identity.visitors.map(&:id)
      return {} if visitor_ids.empty?

      Session.where(visitor_id: visitor_ids)
        .where.not(channel: nil)
        .group(:channel)
        .count
    end

    def compute_total_revenue(identity)
      identity.conversions.sum(:revenue).to_f
    end
  end
end
