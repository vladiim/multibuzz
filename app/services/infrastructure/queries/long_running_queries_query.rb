# frozen_string_literal: true

module Infrastructure
  module Queries
    class LongRunningQueriesQuery
      def call
        ActiveRecord::Base.connection.execute(<<-SQL.squish).first["count"].to_i
          SELECT count(*)
          FROM pg_stat_activity
          WHERE state = 'active'
            AND query NOT ILIKE '%pg_stat_activity%'
            AND now() - query_start > interval '#{::Infrastructure::LONG_QUERY_WARNING_SECONDS} seconds'
        SQL
      end
    end
  end
end
