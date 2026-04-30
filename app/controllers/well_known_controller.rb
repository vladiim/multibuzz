# frozen_string_literal: true

class WellKnownController < ApplicationController
  CACHE_DURATION = 1.hour

  def llms
    expires_in CACHE_DURATION, public: true
    render plain: render_to_string("well_known/llms"), content_type: "text/plain"
  end

  def llms_full
    expires_in CACHE_DURATION, public: true
    render plain: render_to_string("well_known/llms_full"), content_type: "text/plain"
  end
end
