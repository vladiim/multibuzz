# frozen_string_literal: true

module Demo
  module Dashboard
    class FunnelController < ApplicationController
      def show
        @demo_mode = true
        @filter_params = {}
        @result = ::Dashboard::Dummy::FunnelDataService.new.call
      end
    end
  end
end
