# frozen_string_literal: true

class DemoController < ApplicationController
  def show
    @demo_data = Demo::DataGeneratorService.new.call
    @selected_model = params[:model] || AttributionAlgorithms::LINEAR
  end

  def attribution
    @demo_data = Demo::DataGeneratorService.new.call
    @selected_model = params[:model] || AttributionAlgorithms::LINEAR

    render partial: "demo/attribution", locals: {
      demo_data: @demo_data,
      selected_model: @selected_model
    }
  end
end
