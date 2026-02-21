# frozen_string_literal: true

class SitemapEntry
  attr_reader :loc, :lastmod, :changefreq, :priority

  def initialize(loc:, lastmod:, changefreq:, priority:)
    @loc = loc
    @lastmod = lastmod
    @changefreq = changefreq
    @priority = priority
  end

  def lastmod_iso
    lastmod.to_date.iso8601
  end
end
