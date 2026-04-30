# frozen_string_literal: true

class PagesController < ApplicationController
  def home
  end

  def about
  end

  def pricing
  end

  def pricing_md
    expires_in 1.hour, public: true
    render plain: render_to_string("pages/pricing_md"), content_type: "text/plain"
  end

  def privacy
  end

  def terms
  end

  def cookies
  end
end
