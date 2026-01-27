require "test_helper"

class SitemapEntryTest < ActiveSupport::TestCase
  test "stores all attributes" do
    entry = SitemapEntry.new(
      loc: "https://mbuzz.co/",
      lastmod: Date.new(2026, 1, 28),
      changefreq: "weekly",
      priority: 1.0
    )

    assert_equal "https://mbuzz.co/", entry.loc
    assert_equal Date.new(2026, 1, 28), entry.lastmod
    assert_equal "weekly", entry.changefreq
    assert_equal 1.0, entry.priority
  end

  test "lastmod_iso returns ISO 8601 date format" do
    entry = SitemapEntry.new(
      loc: "https://mbuzz.co/",
      lastmod: Date.new(2026, 1, 28),
      changefreq: "weekly",
      priority: 1.0
    )

    assert_equal "2026-01-28", entry.lastmod_iso
  end

  test "lastmod_iso handles DateTime objects" do
    entry = SitemapEntry.new(
      loc: "https://mbuzz.co/",
      lastmod: DateTime.new(2026, 1, 28, 14, 30, 0),
      changefreq: "weekly",
      priority: 1.0
    )

    assert_equal "2026-01-28", entry.lastmod_iso
  end

  test "lastmod_iso handles Time objects" do
    entry = SitemapEntry.new(
      loc: "https://mbuzz.co/",
      lastmod: Time.new(2026, 1, 28, 14, 30, 0),
      changefreq: "weekly",
      priority: 1.0
    )

    assert_equal "2026-01-28", entry.lastmod_iso
  end
end
