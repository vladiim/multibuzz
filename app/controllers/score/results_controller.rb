# frozen_string_literal: true

module Score
  class ResultsController < ApplicationController
    layout "score"

    def show
      @answers = Score.decode_answers(params[:code])

      render plain: "Invalid result code", status: :not_found unless @answers
    end
  end
end
