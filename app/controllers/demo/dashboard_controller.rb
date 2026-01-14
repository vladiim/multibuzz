module Demo
  class DashboardController < ApplicationController
    def show
      @demo_mode = true
      @clv_mode = demo_clv_mode?
    end

    private

    def demo_clv_mode?
      session[:demo_clv_mode] == "clv"
    end
  end
end
