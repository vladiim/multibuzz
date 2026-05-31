# frozen_string_literal: true

module CustomDimensions
  # Re-materialises ad_spend_records.metadata for a single connection from its
  # stored campaign fields (no ad-platform API call). Each row's metadata is
  # rebuilt as connection metadata + resolved dimensions, so keys for deleted
  # dimensions drop off (clear-then-recompute).
  class ConnectionBackfill
    def initialize(connection)
      @connection = connection
    end

    def call
      connection.ad_spend_records.find_each { |record| restamp(record) }
    end

    private

    attr_reader :connection

    def restamp(record)
      record.update_columns(metadata: materialised_metadata(record))
    end

    def materialised_metadata(record)
      base_metadata.merge(resolver.call(record))
    end

    def base_metadata
      @base_metadata ||= connection.metadata.is_a?(Hash) ? connection.metadata : {}
    end

    def resolver
      @resolver ||= Resolver.for_connection(connection)
    end
  end
end
