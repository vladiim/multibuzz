# frozen_string_literal: true

# Query object for the admin index. Takes the raw filter params from the
# controller, returns an ordered ConversionDispatch relation with each
# filter applied. Empty params returns every dispatch, most-recent-first.
#
# Per CLAUDE.md "Query Object: Complex queries, initialize(scope) + call,
# returns domain structures (NOT success/fail, does NOT inherit
# ApplicationService)". Unknown account prefix_ids and malformed dates
# resolve to "filter not applied", not "no results" — callers can still
# add explicit guards if a different policy is needed.
module ConversionDispatches
  class AdminFilterQuery
    def initialize(params)
      @params = params || {}
    end

    def call
      base_scope
        .then { |scope| narrow_by_status(scope) }
        .then { |scope| narrow_by_account(scope) }
        .then { |scope| narrow_by_destination(scope) }
        .then { |scope| narrow_by_from(scope) }
        .then { |scope| narrow_by_to(scope) }
    end

    private

    attr_reader :params

    def base_scope
      ConversionDispatch
        .includes(:conversion, :conversion_destination, :account)
        .order(created_at: :desc)
    end

    def narrow_by_status(scope)
      status.present? ? scope.where(status: status) : scope
    end

    def narrow_by_account(scope)
      return scope if params[:account_id].blank?
      return scope.none unless filter_account

      scope.where(account: filter_account)
    end

    def narrow_by_destination(scope)
      destination_id.present? ? scope.where(conversion_destination_id: destination_id) : scope
    end

    def narrow_by_from(scope)
      parsed_from ? scope.where("conversion_dispatches.created_at >= ?", parsed_from) : scope
    end

    def narrow_by_to(scope)
      parsed_to ? scope.where("conversion_dispatches.created_at < ?", parsed_to + 1.day) : scope
    end

    def status         = params[:status]
    def destination_id = params[:conversion_destination_id]
    def filter_account = @filter_account ||= Account.find_by_prefix_id(params[:account_id])
    def parsed_from    = @parsed_from    ||= safe_parse_date(params[:from])
    def parsed_to      = @parsed_to      ||= safe_parse_date(params[:to])

    def safe_parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
