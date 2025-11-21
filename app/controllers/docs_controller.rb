class DocsController < ApplicationController
  layout "docs"

  ALLOWED_PAGES = %w[getting-started authentication api-reference examples].freeze

  def show
    page_slug = params[:page]

    return render_404 unless ALLOWED_PAGES.include?(page_slug)

    @page_name = page_slug.tr("-", "_")
  end

  private

  def render_404
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end
