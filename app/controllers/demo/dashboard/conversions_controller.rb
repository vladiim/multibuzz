module Demo
  module Dashboard
    class ConversionsController < ApplicationController
      def show
        @demo_mode = true
        @clv_mode = demo_clv_mode?
        @filter_params = { models: [ default_model ] }

        @clv_mode ? load_clv_data : load_transactions_data
      end

      private

      def demo_clv_mode?
        session[:demo_clv_mode] == "clv"
      end

      def load_clv_data
        @clv_data = ::Dashboard::Dummy::ClvDataService.new.call[:data]
      end

      def load_transactions_data
        @comparison_mode = false
        @results = [ single_result ]
      end

      def single_result
        { model: default_model, result: ::Dashboard::Dummy::ConversionsDataService.new.call }
      end

      def default_model
        @default_model ||= AttributionModel.new(name: "linear", algorithm: AttributionAlgorithms::LINEAR)
      end
    end
  end
end
