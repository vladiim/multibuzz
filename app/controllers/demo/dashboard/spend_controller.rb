# frozen_string_literal: true

module Demo
  module Dashboard
    class SpendController < ApplicationController
      def show
        @demo_mode = true
        @data = ::Dashboard::Dummy::SpendDataService.new.call[:data]
      end
    end
  end
end
