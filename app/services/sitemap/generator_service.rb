# frozen_string_literal: true

module Sitemap
  class GeneratorService
    STATIC_PAGES = [
      { path: :root_url, priority: PRIORITY_HIGHEST, changefreq: CHANGEFREQ_WEEKLY },
      { path: :academy_url, priority: PRIORITY_HIGH, changefreq: CHANGEFREQ_DAILY },
      { path: :score_url, priority: PRIORITY_HIGH, changefreq: CHANGEFREQ_MONTHLY },
      { path: :demo_dashboard_url, priority: PRIORITY_MEDIUM_LOW, changefreq: CHANGEFREQ_MONTHLY },
      { path: :about_url, priority: PRIORITY_LOW, changefreq: CHANGEFREQ_MONTHLY },
      { path: :contact_url, priority: PRIORITY_LOWEST, changefreq: CHANGEFREQ_YEARLY }
    ].freeze

    SECTION_PRIORITY = PRIORITY_MEDIUM_HIGH
    SECTION_CHANGEFREQ = CHANGEFREQ_WEEKLY

    DOC_PRIORITY = PRIORITY_MEDIUM
    DOC_CHANGEFREQ = CHANGEFREQ_WEEKLY

    ARTICLE_CHANGEFREQ = CHANGEFREQ_MONTHLY

    def self.call
      new.call
    end

    def call
      static_entries + doc_entries + section_entries + article_entries
    end

    private

    def static_entries
      STATIC_PAGES.map do |page|
        SitemapEntry.new(
          loc: url_helpers.public_send(page[:path], host: App::HOST),
          lastmod: Date.current,
          changefreq: page[:changefreq],
          priority: page[:priority]
        )
      end
    end

    def doc_entries
      DocsController::ALLOWED_PAGES.map do |page|
        SitemapEntry.new(
          loc: url_helpers.docs_url(page, host: App::HOST),
          lastmod: Date.current,
          changefreq: DOC_CHANGEFREQ,
          priority: DOC_PRIORITY
        )
      end
    end

    def section_entries
      Article::SECTIONS.map do |section|
        SitemapEntry.new(
          loc: url_helpers.academy_section_url(section, host: App::HOST),
          lastmod: latest_article_date_in_section(section),
          changefreq: SECTION_CHANGEFREQ,
          priority: SECTION_PRIORITY
        )
      end
    end

    def article_entries
      Articles::Repository.published.map do |article|
        SitemapEntry.new(
          loc: url_helpers.article_url(article.slug, host: App::HOST),
          lastmod: article.published_at,
          changefreq: ARTICLE_CHANGEFREQ,
          priority: article_priority(article)
        )
      end
    end

    def article_priority(article)
      ARTICLE_PRIORITY_MAP.fetch(article.priority, DEFAULT_ARTICLE_PRIORITY)
    end

    def latest_article_date_in_section(section)
      articles = Articles::Repository.published.select { |a| a.section == section }
      articles.map(&:published_at).compact.max || Date.current
    end

    def url_helpers
      Rails.application.routes.url_helpers
    end
  end
end
