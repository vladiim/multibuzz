# frozen_string_literal: true

module UnifiedFeed
  class QueryService
    SOURCES = {
      event:      { timestamp: :occurred_at, includes: [ :session, :visitor ] },
      conversion: { timestamp: :converted_at, includes: [ :visitor ] },
      identify:   { timestamp: :last_identified_at, includes: [] },
      session:    { timestamp: :started_at, includes: [ :visitor ] },
      visitor:    { timestamp: :created_at, includes: [] }
    }.freeze

    def initialize(account, limit: 100, test_only: false)
      @account = account
      @limit = limit
      @test_only = test_only
    end

    def call
      SOURCES
        .flat_map { |feed_type, config| fetch(feed_type, config) }
        .sort_by(&:occurred_at)
        .reverse
        .first(limit)
    end

    private

    attr_reader :account, :limit, :test_only

    def fetch(feed_type, config)
      scope = scoped_relation(feed_type, config)
      records = scope
        .order(config[:timestamp] => :desc)
        .limit(per_source_limit)

      records.map do |record|
        FeedItem.new(
          feed_type: feed_type,
          occurred_at: record.public_send(config[:timestamp]),
          record: record
        )
      end
    end

    def scoped_relation(feed_type, config)
      relation = base_relation(feed_type)
      relation = relation.includes(*config[:includes]) if config[:includes].any?
      apply_environment_scope(relation)
    end

    def base_relation(feed_type)
      case feed_type
      when :event      then account.events
      when :conversion then account.conversions
      when :identify   then account.identities
      when :session    then account.sessions
      when :visitor    then account.visitors
      end
    end

    def apply_environment_scope(relation)
      test_only ? relation.test_data : relation.production
    end

    def per_source_limit
      limit
    end
  end
end
