# frozen_string_literal: true

module Demo
  module Dashboard
    class ConversionsController < ApplicationController
      def show
        @demo_mode = true
        @clv_mode = demo_clv_mode?
        @selected_models = selected_models
        @comparison_mode = @selected_models.length > 1
        @filter_params = { models: @selected_models, metric: params[:metric] }

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
        @results = @selected_models.map do |model|
          { model: model, result: ::Dashboard::Dummy::ConversionsDataService.new.call }
        end
      end

      def selected_models
        model_params = Array(params[:models]).reject(&:blank?)
        model_params = [ "linear" ] if model_params.empty?

        model_params.take(2).map do |model_key|
          build_demo_model(model_key)
        end
      end

      def build_demo_model(model_key)
        algorithm = DEMO_MODELS[model_key] || AttributionAlgorithms::LINEAR
        # Create a struct-like object that responds to the same interface as AttributionModel
        DemoModel.new(model_key, algorithm)
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

      # Simple struct to mimic AttributionModel interface for demo purposes
      DemoModel = Struct.new(:name, :algorithm) do
        def prefix_id
          name
        end
      end
    end
  end
end
