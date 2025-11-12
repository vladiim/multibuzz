class DocsController < ApplicationController
  layout "docs"

  ALLOWED_PAGES = %w[getting-started authentication api-reference examples].freeze

  def show
    page_slug = params[:page]

    return render_404 unless ALLOWED_PAGES.include?(page_slug)

    # Convert dashes to underscores for file lookup
    # e.g., 'getting-started' -> 'getting_started.md.erb'
    @page_name = page_slug.tr("-", "_")

    render template: "docs/#{@page_name}", formats: [:md]
  rescue ActionView::MissingTemplate
    render_404
  end

  private

  def render_404
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end
