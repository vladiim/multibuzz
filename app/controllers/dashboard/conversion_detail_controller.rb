# frozen_string_literal: true

module Dashboard
  class ConversionDetailController < BaseController
    include Pagination

    def index
      @conversions = paginate(conversions_scope)
      @total_count = conversions_scope.count
    end

    def show
      @conversion = detail_query.call(params[:id])
      head(:not_found) unless @conversion
    end

    private

    def conversions_scope
      @conversions_scope ||= scoped_conversions
        .includes(:visitor, :identity)
        .then { |scope| apply_type_filter(scope) }
        .order(converted_at: :desc)
    end

    def apply_type_filter(scope)
      return scope unless params[:conversion_type].present?

      scope.where(conversion_type: params[:conversion_type])
    end

    def detail_query
      @detail_query ||= ConversionDetailQuery.new(current_account)
    end
  end
end
