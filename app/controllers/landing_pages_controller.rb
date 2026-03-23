# frozen_string_literal: true

class LandingPagesController < ApplicationController
  layout "landing_page"

  def show
    @page = LandingPages::Registry.find(params[:slug])
    raise ActionController::RoutingError, "Not Found" unless @page

    render @page.template
  end
end
