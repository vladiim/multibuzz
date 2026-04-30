# frozen_string_literal: true

module AdPlatforms
  # Re-stamps every AdSpendRecord that belongs to the given connection with the
  # connection's current `metadata`. Run when an operator edits the metadata on
  # an existing connection so historical spend rolls up against the new tag.
  #
  # Full overwrite, not deep merge — matches the connection's metadata exactly.
  # Account-scoped via the connection's foreign key; no cross-account writes.
  class MetadataBackfillService < ApplicationService
    def initialize(connection)
      @connection = connection
    end

    private

    attr_reader :connection

    def run
      success_result(records_updated: spend_records.update_all(metadata: connection.metadata))
    end

    def spend_records
      connection.ad_spend_records
    end
  end
end
