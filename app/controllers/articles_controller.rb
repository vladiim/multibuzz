class ArticlesController < ApplicationController
  layout "article"

  before_action :set_article, only: :show
  before_action :require_published, only: :show
  before_action :set_section, only: :section
  before_action :validate_section, only: :section

  def index
    @sections = Articles::Repository.by_section
    @featured = Articles::Repository.featured
  end

  def show
    @meta = Articles::MetaTagsBuilder.new(@article).call
  end

  def section
    @articles = Articles::Repository.in_section(@section)
  end

  private

  def set_article
    @article = Articles::Repository.find_by_slug!(params[:slug])
  rescue ActiveRecord::RecordNotFound
    render_not_found
  end

  def require_published
    render_not_found unless @article.published?
  end

  def set_section
    @section = params[:section]
  end

  def validate_section
    render_not_found unless Article::SECTIONS.include?(@section)
  end

  def render_not_found
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end
