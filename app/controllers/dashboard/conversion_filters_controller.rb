# frozen_string_literal: true

module Dashboard
  class ConversionFiltersController < BaseController
    def dimensions
      render json: dimensions_result[:dimensions]
    end

    def values
      render json: values_result[:values] || []
    end

    def add_row
      render turbo_stream: turbo_stream.append(
        "conversion-filters",
        partial: "filter_row",
        locals: { dimensions: dimensions_list, index: row_index }
      )
    end

    def remove_row
      render turbo_stream: turbo_stream.remove(params[:row_id])
    end

    private

    def dimensions_result
      @dimensions_result ||= ConversionDimensionsService.new(current_account).call
    end

    def dimensions_list
      @dimensions_list ||= dimensions_result[:dimensions]
    end

    def values_result
      @values_result ||= ConversionValuesService.new(
        current_account,
        field: params[:field],
        query: params[:query],
        test_mode: test_mode?
      ).call
    end

    def row_index
      @row_index ||= params[:index]&.to_i || 0
    end
  end
end
