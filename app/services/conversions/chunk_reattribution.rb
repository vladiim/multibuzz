# frozen_string_literal: true

module Conversions
  # Reattributes one bounded chunk of conversions. Stops at a wall-clock budget
  # and re-enqueues the remainder, so no single job can run unbounded.
  class ChunkReattribution
    BUDGET = 5.minutes
    STATEMENT_TIMEOUT_MS = 30_000

    def initialize(batch, conversion_ids, deadline: BUDGET.from_now)
      @batch = batch
      @conversion_ids = conversion_ids
      @deadline = deadline
    end

    def call
      remaining = with_statement_timeout { process_within_budget }
      remaining.any? ? ReattributionChunkJob.perform_later(batch.id, remaining) : finalize
    end

    private

    attr_reader :batch, :conversion_ids, :deadline

    def process_within_budget
      conversion_ids.each_with_index do |id, index|
        return conversion_ids.drop(index) if Time.current >= deadline

        reattribute(id)
      end
      []
    end

    def reattribute(id)
      conversion = batch.account.conversions.find_by(id: id)
      return batch.increment_failed! unless conversion

      result = ReattributionService.new(conversion, conversion_paths: conversion_paths).call
      result[:success] ? batch.increment_processed! : batch.increment_failed!
    end

    def conversion_paths
      @conversion_paths ||= Attribution::Markov::ConversionPathsQuery.cached_for(batch.account)
    end

    def finalize
      batch.mark_completed! if batch.processed + batch.failed >= batch.total
    end

    def with_statement_timeout
      connection.execute("SET statement_timeout = #{STATEMENT_TIMEOUT_MS}")
      yield
    ensure
      connection.execute("SET statement_timeout = DEFAULT")
    end

    def connection
      ActiveRecord::Base.connection
    end
  end
end
