require "test_helper"

class SitemapControllerTest < ActionDispatch::IntegrationTest
  test "sitemap returns XML with correct content type" do
    get sitemap_path(format: :xml)

    assert_response :success
    assert_equal "application/xml; charset=utf-8", response.content_type
  end

  test "sitemap includes homepage with highest priority" do
    get sitemap_path(format: :xml)

    assert_includes response.body, "<loc>http://#{App::HOST}/</loc>"
    assert_includes response.body, "<priority>#{Sitemap::PRIORITY_HIGHEST}</priority>"
  end

  test "sitemap includes academy" do
    get sitemap_path(format: :xml)

    assert_includes response.body, "<loc>http://#{App::HOST}/academy</loc>"
  end

  test "sitemap includes documentation pages" do
    get sitemap_path(format: :xml)

    assert_includes response.body, "http://#{App::HOST}/docs/getting-started"
    assert_includes response.body, "http://#{App::HOST}/docs/authentication"
  end

  test "sitemap includes academy sections" do
    get sitemap_path(format: :xml)

    Article::SECTIONS.each do |section|
      assert_includes response.body, "http://#{App::HOST}/academy/#{section}", "Missing section: #{section}"
    end
  end

  test "sitemap includes demo dashboard" do
    get sitemap_path(format: :xml)

    assert_includes response.body, "http://#{App::HOST}/demo/dashboard"
  end

  test "sitemap has valid XML structure" do
    get sitemap_path(format: :xml)

    doc = Nokogiri::XML(response.body)
    assert doc.errors.empty?, "Invalid XML: #{doc.errors.join(', ')}"
    assert_equal "urlset", doc.root.name
    assert_equal "http://www.sitemaps.org/schemas/sitemap/0.9", doc.root.namespace.href
  end

  test "sitemap entries have required elements" do
    get sitemap_path(format: :xml)

    doc = Nokogiri::XML(response.body)
    doc.css("url").each do |url_node|
      assert url_node.at_css("loc").present?, "Missing loc element"
      assert url_node.at_css("lastmod").present?, "Missing lastmod element"
      assert url_node.at_css("changefreq").present?, "Missing changefreq element"
      assert url_node.at_css("priority").present?, "Missing priority element"
    end
  end

  test "sitemap lastmod dates are in ISO 8601 format" do
    get sitemap_path(format: :xml)

    doc = Nokogiri::XML(response.body)
    doc.css("lastmod").each do |lastmod|
      assert_match(/\d{4}-\d{2}-\d{2}/, lastmod.text, "Invalid date format: #{lastmod.text}")
    end
  end

  test "sitemap is cached for 1 hour" do
    get sitemap_path(format: :xml)

    assert_equal "max-age=3600, public", response.headers["Cache-Control"]
  end
end
