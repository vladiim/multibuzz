# frozen_string_literal: true

require "test_helper"

class ArticlesControllerTest < ActionDispatch::IntegrationTest
  test "index renders academy page" do
    with_test_articles do
      get academy_path

      assert_response :success
      assert_select "h1", /Academy/i
    end
  end

  test "index lists published articles" do
    with_test_articles do
      get academy_path

      assert_response :success
      assert_select "[data-testid='article-card']", count: 1
    end
  end

  test "show renders article" do
    with_test_articles do
      get article_path("test-article")

      assert_response :success
      assert_select "h1", "Test Article"
    end
  end

  test "show returns 404 for non-existent article" do
    with_test_articles do
      get article_path("non-existent")

      assert_response :not_found
    end
  end

  test "show returns 404 for draft articles" do
    with_test_articles(status: Article::STATUS_DRAFT) do
      get article_path("test-article")

      assert_response :not_found
    end
  end

  test "show returns 404 for future published_at" do
    with_test_articles(published_at: Date.tomorrow) do
      get article_path("test-article")

      assert_response :not_found
    end
  end

  test "section filters by section" do
    with_test_articles do
      get academy_section_path("fundamentals")

      assert_response :success
      assert_select "[data-testid='article-card']", count: 1
    end
  end

  test "section returns 404 for invalid section" do
    with_test_articles do
      get "/academy/invalid-section"

      assert_response :not_found
    end
  end

  private

  def with_test_articles(overrides = {})
    defaults = {
      title: "Test Article",
      slug: "test-article",
      description: "A test description",
      published_at: Date.yesterday,
      section: "fundamentals",
      status: Article::STATUS_PUBLISHED
    }

    frontmatter = defaults.merge(overrides)

    content = <<~CONTENT
      ---
      title: "#{frontmatter[:title]}"
      slug: "#{frontmatter[:slug]}"
      description: "#{frontmatter[:description]}"
      published_at: #{frontmatter[:published_at]}
      section: #{frontmatter[:section]}
      status: #{frontmatter[:status]}
      ---

      ## Content

      Test body content.
    CONTENT

    original_path = Article::CONTENT_PATH
    test_dir = Rails.root.join("tmp/test_articles_#{SecureRandom.hex(4)}")

    begin
      FileUtils.mkdir_p(test_dir.join("fundamentals"))
      File.write(test_dir.join("fundamentals/test-article.md.erb"), content)

      Article.send(:remove_const, :CONTENT_PATH)
      Article.const_set(:CONTENT_PATH, test_dir)

      Articles::Repository.reload!

      yield
    ensure
      Article.send(:remove_const, :CONTENT_PATH)
      Article.const_set(:CONTENT_PATH, original_path)
      Articles::Repository.reload!
      FileUtils.rm_rf(test_dir)
    end
  end
end
