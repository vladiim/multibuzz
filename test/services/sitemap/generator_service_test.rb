# frozen_string_literal: true

require "test_helper"

class Sitemap::GeneratorServiceTest < ActiveSupport::TestCase
  test "returns array of SitemapEntry objects" do
    entries = service.call

    assert_kind_of Array, entries
    assert entries.all? { |e| e.is_a?(SitemapEntry) }
  end

  test "includes homepage with highest priority" do
    entries = service.call
    homepage = entries.find { |e| e.loc.end_with?("/") }

    assert_not_nil homepage, "Homepage not found in sitemap"
    assert_in_delta(1.0, homepage.priority)
    assert_equal "weekly", homepage.changefreq
  end

  test "includes academy page" do
    entries = service.call
    academy = entries.find { |e| e.loc.include?("/academy") && !e.loc.include?("/academy/") }

    assert_not_nil academy, "Academy page not found in sitemap"
    assert_in_delta(0.9, academy.priority)
    assert_equal "daily", academy.changefreq
  end

  test "includes about page" do
    entries = service.call
    about = entries.find { |e| e.loc.include?("/about") }

    assert_not_nil about, "About page not found in sitemap"
    assert_in_delta(0.5, about.priority)
  end

  test "includes demo dashboard" do
    entries = service.call
    demo = entries.find { |e| e.loc.include?("/demo/dashboard") }

    assert_not_nil demo, "Demo dashboard not found in sitemap"
    assert_in_delta(0.6, demo.priority)
  end

  test "includes contact page" do
    entries = service.call
    contact = entries.find { |e| e.loc.include?("/contact") }

    assert_not_nil contact, "Contact page not found in sitemap"
    assert_in_delta(0.4, contact.priority)
    assert_equal "yearly", contact.changefreq
  end

  test "includes documentation pages" do
    entries = service.call
    locs = entries.map(&:loc)

    assert locs.any? { |loc| loc.include?("/docs/getting-started") }, "Missing getting-started doc"
    assert locs.any? { |loc| loc.include?("/docs/authentication") }, "Missing authentication doc"
  end

  test "includes academy section pages" do
    entries = service.call
    locs = entries.map(&:loc)

    Article::SECTIONS.each do |section|
      assert locs.any? { |loc| loc.include?("/academy/#{section}") }, "Missing section: #{section}"
    end
  end

  test "section pages have priority 0.8" do
    entries = service.call
    section_entry = entries.find { |e| e.loc.include?("/academy/fundamentals") }

    assert_not_nil section_entry
    assert_in_delta(0.8, section_entry.priority)
    assert_equal "weekly", section_entry.changefreq
  end

  test "entries have valid lastmod dates" do
    entries = service.call

    entries.each do |entry|
      assert_respond_to entry.lastmod, :to_date, "lastmod should respond to to_date for: #{entry.loc}"
      assert_match(/\d{4}-\d{2}-\d{2}/, entry.lastmod_iso, "Invalid lastmod format for: #{entry.loc}")
    end
  end

  test "all URLs use correct host" do
    entries = service.call

    entries.each do |entry|
      assert entry.loc.start_with?("http"), "URL should be absolute: #{entry.loc}"
    end
  end

  private

  def service
    @service ||= Sitemap::GeneratorService.new
  end
end
