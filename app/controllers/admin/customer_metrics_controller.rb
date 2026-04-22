# frozen_string_literal: true

module Admin
  class CustomerMetricsController < BaseController
    def index
      respond_to do |format|
        format.html
        format.csv { send_data csv_body, filename: "customer_metrics_#{Date.current}.csv", type: "text/csv" }
      end
    end

    private

    def rows
      @rows ||= CustomerMetricsQuery.new.call
    end

    def csv_body
      CustomerMetricsCsv.new(rows).generate
    end

    helper_method :rows
  end
end
