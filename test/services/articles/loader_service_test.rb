require "test_helper"

module Articles
  class LoaderServiceTest < ActiveSupport::TestCase
    test "loads articles from content directory" do
      with_test_article("fundamentals/test-article.md.erb", valid_frontmatter) do
        articles = LoaderService.call

        assert_equal 1, articles.size
        assert_equal "Test Article", articles.first.title
        assert_equal "test-article", articles.first.slug
      end
    end

    test "returns empty array when no articles exist" do
      with_empty_content_dir do
        articles = LoaderService.call

        assert_equal [], articles
      end
    end

    test "skips files with invalid frontmatter" do
      with_test_article("fundamentals/invalid.md.erb", "---\n---\nNo frontmatter") do
        articles = LoaderService.call

        assert_equal [], articles
      end
    end

    test "loads articles from nested directories" do
      with_test_articles(
        "fundamentals/article-one.md.erb" => valid_frontmatter(title: "One", slug: "one"),
        "models/article-two.md.erb" => valid_frontmatter(title: "Two", slug: "two")
      ) do
        articles = LoaderService.call

        assert_equal 2, articles.size
        assert_equal %w[one two], articles.map(&:slug).sort
      end
    end

    test "sets file_path on loaded articles" do
      with_test_article("fundamentals/test-article.md.erb", valid_frontmatter) do
        article = LoaderService.call.first

        assert article.file_path.end_with?("fundamentals/test-article.md.erb")
      end
    end

    private

    def valid_frontmatter(overrides = {})
      defaults = {
        title: "Test Article",
        slug: "test-article",
        description: "A test description",
        published_at: "2025-01-15",
        section: "fundamentals",
        status: "published"
      }

      frontmatter = defaults.merge(overrides)

      <<~CONTENT
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
    end

    def with_test_article(path, content)
      with_test_articles(path => content) { yield }
    end

    def with_test_articles(articles)
      original_path = Article::CONTENT_PATH
      test_dir = Rails.root.join("tmp/test_articles_#{SecureRandom.hex(4)}")

      begin
        FileUtils.mkdir_p(test_dir)

        articles.each do |path, content|
          full_path = test_dir.join(path)
          FileUtils.mkdir_p(File.dirname(full_path))
          File.write(full_path, content)
        end

        Article.send(:remove_const, :CONTENT_PATH)
        Article.const_set(:CONTENT_PATH, test_dir)

        yield
      ensure
        Article.send(:remove_const, :CONTENT_PATH)
        Article.const_set(:CONTENT_PATH, original_path)
        FileUtils.rm_rf(test_dir)
      end
    end

    def with_empty_content_dir
      with_test_articles({}) { yield }
    end
  end
end
