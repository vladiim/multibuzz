# frozen_string_literal: true

class SitemapController < ApplicationController
  CACHE_DURATION = 1.hour

  def show
    @entries = Sitemap::GeneratorService.call

    expires_in CACHE_DURATION, public: true

    respond_to do |format|
      format.xml { render layout: false }
    end
  end
end
