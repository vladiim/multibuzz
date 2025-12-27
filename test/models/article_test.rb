require "test_helper"

class ArticleTest < ActiveSupport::TestCase
  test "parses frontmatter from content" do
    content = <<~CONTENT
      ---
      title: "Test Article"
      slug: "test-article"
      description: "A test description"
      published_at: 2025-01-15
      section: fundamentals
      status: published
      ---

      ## Content Here

      This is the body.
    CONTENT

    article = Article.from_content(content, file_path: "/fake/path.md.erb")

    assert_equal "Test Article", article.title
    assert_equal "test-article", article.slug
    assert_equal "A test description", article.description
    assert_equal Date.new(2025, 1, 15), article.published_at
    assert_equal "fundamentals", article.section
    assert_equal "published", article.status
  end

  test "published? returns true when status is published and date is past" do
    article = build_article(status: "published", published_at: Date.yesterday)

    assert article.published?
  end

  test "published? returns false when status is draft" do
    article = build_article(status: "draft", published_at: Date.yesterday)

    refute article.published?
  end

  test "published? returns false when published_at is in the future" do
    article = build_article(status: "published", published_at: Date.tomorrow)

    refute article.published?
  end

  test "seo_title falls back to title" do
    article = build_article(title: "My Title", seo: {})

    assert_equal "My Title", article.seo_title
  end

  test "seo_title uses seo.title when present" do
    article = build_article(title: "My Title", seo: { "title" => "SEO Title" })

    assert_equal "SEO Title", article.seo_title
  end

  test "reading_time calculates from word count" do
    article = build_article(content: "word " * 400)

    assert_equal 2, article.reading_time
  end

  test "tldr returns aeo tldr" do
    article = build_article(aeo: { "tldr" => "Quick summary" })

    assert_equal "Quick summary", article.tldr
  end

  test "key_takeaways returns empty array when not present" do
    article = build_article(aeo: {})

    assert_equal [], article.key_takeaways
  end

  test "faq returns empty array when not present" do
    article = build_article(aeo: {})

    assert_equal [], article.faq
  end

  test "to_param returns slug" do
    article = build_article(slug: "my-slug")

    assert_equal "my-slug", article.to_param
  end

  test "schema_json_ld returns valid structure" do
    article = build_article(
      title: "Test",
      description: "Desc",
      published_at: Date.new(2025, 1, 15),
      tags: %w[tag1 tag2],
      category: "Fundamentals"
    )

    json = article.schema_json_ld

    assert_equal "https://schema.org", json[:"@context"]
    assert_equal "Article", json[:"@type"]
    assert_equal "Test", json[:headline]
    assert_equal "Desc", json[:description]
    assert_equal "tag1, tag2", json[:keywords]
  end

  test "valid sections" do
    assert_includes Article::SECTIONS, "fundamentals"
    assert_includes Article::SECTIONS, "models"
    assert_includes Article::SECTIONS, "implementation"
  end

  private

  def build_article(attrs = {})
    defaults = {
      title: "Default Title",
      slug: "default-slug",
      description: "Default description",
      published_at: Date.current,
      section: "fundamentals",
      status: "published",
      seo: {},
      aeo: {},
      schema: {},
      tags: [],
      category: "Test",
      content: "Test content",
      file_path: "/fake/path.md.erb"
    }

    Article.new(defaults.merge(attrs))
  end
end
