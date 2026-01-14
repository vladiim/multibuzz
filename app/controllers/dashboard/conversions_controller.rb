module Dashboard
  class ConversionsController < BaseController
    def show
      @filter_params = filter_params
      @clv_mode = clv_mode?
      @demo_mode = demo_mode?

      clv_mode? ? load_clv_data : load_transactions_data
    end

    private

    def load_clv_data
      @clv_data = if demo_mode?
        Dashboard::Dummy::ClvDataService.call[:data]
      else
        Dashboard::ClvDataService.new(current_account, filter_params).call[:data]
      end
    end

    def load_transactions_data
      @comparison_mode = comparison_mode?
      @results = @comparison_mode ? comparison_results : [ single_result ]
    end

    def comparison_mode?
      selected_attribution_models.length == 2
    end

    def comparison_results
      selected_attribution_models.map { |model| result_for_model(model) }
    end

    def single_result
      result_for_model(selected_attribution_models.first)
    end

    def result_for_model(model)
      {
        model: model,
        result: demo_mode? ? dummy_conversions_result : real_conversions_result(model)
      }
    end

    def dummy_conversions_result
      Dashboard::Dummy::ConversionsDataService.call
    end

    def real_conversions_result(model)
      Dashboard::ConversionsDataService.new(
        current_account,
        filter_params.merge(models: [ model ])
      ).call
    end
  end
end
