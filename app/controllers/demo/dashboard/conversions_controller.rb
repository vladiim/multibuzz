module Demo
  module Dashboard
    class ConversionsController < ApplicationController
      def show
        @demo_mode = true
        @clv_mode = demo_clv_mode?
        @selected_model = selected_model
        @filter_params = { models: [ @selected_model ], metric: params[:metric] }

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
        { model: @selected_model, result: ::Dashboard::Dummy::ConversionsDataService.new.call }
      end

      def selected_model
        model_param = params[:model] || "linear"
        algorithm = DEMO_MODELS[model_param] || AttributionAlgorithms::LINEAR
        AttributionModel.new(name: model_param, algorithm: algorithm)
      end

      DEMO_MODELS = {
        "first_touch" => AttributionAlgorithms::FIRST_TOUCH,
        "last_touch" => AttributionAlgorithms::LAST_TOUCH,
        "linear" => AttributionAlgorithms::LINEAR,
        "time_decay" => AttributionAlgorithms::TIME_DECAY,
        "u_shaped" => AttributionAlgorithms::U_SHAPED,
        "markov_chain" => AttributionAlgorithms::MARKOV_CHAIN,
        "shapley_value" => AttributionAlgorithms::SHAPLEY_VALUE
      }.freeze
    end
  end
end
