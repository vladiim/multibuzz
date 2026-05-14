# frozen_string_literal: true

# Landing page for /admin. Lists every admin tool grouped by category
# from AdminTools::ALL. Inherits skip_marketing_analytics + require_admin
# from Admin::BaseController.
module Admin
  class DashboardController < BaseController
    def index
      @grouped_tools = AdminTools.grouped
    end
  end
end
