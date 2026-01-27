# Spec: XML Sitemap for SEO/AEO

## Overview

Implement a dynamic XML sitemap that includes the homepage and all published articles. The sitemap improves search engine crawling and supports AI engine optimization (AEO) by providing structured metadata about content freshness and priority.

**Goals:**
- Help search engines discover and index all public pages
- Signal content freshness via `lastmod` timestamps
- Indicate page importance via `priority` values
- Support AI crawlers (ChatGPT, Perplexity, Claude) with clean URL structures
- Add sitemap link to footer for user discoverability

---

## Current State

| Component | Status |
|-----------|--------|
| XML Sitemap | Not implemented |
| robots.txt | Empty (only has documentation comment) |
| Footer sitemap link | Not present |
| Article metadata | Has `published_at`, `status`, `priority` in frontmatter |

---

## Sitemap Structure

### Pages to Include

| Page Type | URL Pattern | Route | Priority | Change Frequency |
|-----------|-------------|-------|----------|------------------|
| Homepage | `/` | `root_path` | 1.0 | weekly |
| Academy (article index) | `/academy` | `academy_path` | 0.9 | daily |
| Academy sections | `/academy/:section` | `academy_section_path` | 0.8 | weekly |
| Individual articles | `/articles/:slug` | `article_path` | 0.7 | monthly |
| Documentation | `/docs/:page` | `docs_path` | 0.7 | weekly |
| Demo dashboard | `/demo/dashboard` | `demo_dashboard_path` | 0.6 | monthly |
| About | `/about` | `about_path` | 0.5 | monthly |
| Contact | `/contact` | `contact_path` | 0.4 | yearly |

### Pages to Exclude

| Page Type | Reason |
|-----------|--------|
| Login/Signup | Auth pages, not content |
| Dashboard routes | Private, authenticated content |
| API endpoints | Not indexable content |
| Legal pages (privacy, terms, cookies) | Low SEO value, boilerplate |
| Draft/unpublished articles | Not public |
| Onboarding flows | Private, post-signup |
| Admin routes | Private |

---

## XML Format

### Standard Sitemap (sitemap.xml)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://mbuzz.co/</loc>
    <lastmod>2026-01-28</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>https://mbuzz.co/academy</loc>
    <lastmod>2026-01-28</lastmod>
    <changefreq>daily</changefreq>
    <priority>0.9</priority>
  </url>
  <url>
    <loc>https://mbuzz.co/articles/mta-vs-mmm</loc>
    <lastmod>2026-01-15</lastmod>
    <changefreq>monthly</changefreq>
    <priority>0.7</priority>
  </url>
  <!-- ... more URLs ... -->
</urlset>
```

### Priority Mapping from Article Priority

| Article Priority | Sitemap Priority |
|-----------------|------------------|
| P0 (must have) | 0.8 |
| P1 (high value) | 0.7 |
| P2 (important) | 0.6 |
| P3 (nice to have) | 0.5 |

---

## Implementation

### Route

```ruby
# config/routes.rb
get "sitemap", to: "sitemap#show", defaults: { format: :xml }
```

**URL:** `https://mbuzz.co/sitemap.xml` (via format constraint)

### Controller

```ruby
# app/controllers/sitemap_controller.rb
class SitemapController < ApplicationController
  def show
    @entries = Sitemap::GeneratorService.call

    expires_in 1.hour, public: true

    respond_to do |format|
      format.xml { render layout: false }
    end
  end
end
```

### Service: Sitemap::GeneratorService

```ruby
# app/services/sitemap/generator_service.rb
module Sitemap
  class GeneratorService
    STATIC_PAGES = [
      { path: :root_url, priority: 1.0, changefreq: "weekly" },
      { path: :academy_url, priority: 0.9, changefreq: "daily" },
      { path: :demo_dashboard_url, priority: 0.6, changefreq: "monthly" },
      { path: :about_url, priority: 0.5, changefreq: "monthly" },
      { path: :contact_url, priority: 0.4, changefreq: "yearly" }
    ].freeze

    DOC_PAGES = %w[
      getting-started
      javascript-sdk
      ruby-sdk
      node-sdk
      php-sdk
      python-sdk
      shopify
      conversions
      identify
    ].freeze

    SECTION_PRIORITY = 0.8
    SECTION_CHANGEFREQ = "weekly"
    DOC_PRIORITY = 0.7
    DOC_CHANGEFREQ = "weekly"

    ARTICLE_PRIORITY_MAP = {
      "P0" => 0.8,
      "P1" => 0.7,
      "P2" => 0.6,
      "P3" => 0.5
    }.freeze

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
          loc: url_helpers.public_send(page[:path], host: host),
          lastmod: Date.current,
          changefreq: page[:changefreq],
          priority: page[:priority]
        )
      end
    end

    def doc_entries
      DOC_PAGES.map do |page|
        SitemapEntry.new(
          loc: url_helpers.docs_url(page, host: host),
          lastmod: Date.current,
          changefreq: DOC_CHANGEFREQ,
          priority: DOC_PRIORITY
        )
      end
    end

    def section_entries
      Article::SECTIONS.map do |section|
        SitemapEntry.new(
          loc: url_helpers.academy_section_url(section, host: host),
          lastmod: latest_article_date_in_section(section),
          changefreq: SECTION_CHANGEFREQ,
          priority: SECTION_PRIORITY
        )
      end
    end

    def article_entries
      Articles::Repository.published.map do |article|
        SitemapEntry.new(
          loc: url_helpers.article_url(article.slug, host: host),
          lastmod: article.published_at,
          changefreq: "monthly",
          priority: ARTICLE_PRIORITY_MAP.fetch(article.priority, 0.6)
        )
      end
    end

    def latest_article_date_in_section(section)
      articles = Articles::Repository.published.select { |a| a.section == section }
      articles.map(&:published_at).compact.max || Date.current
    end

    def url_helpers
      Rails.application.routes.url_helpers
    end

    def host
      Rails.application.config.action_mailer.default_url_options[:host] || "mbuzz.co"
    end
  end
end
```

### Value Object: SitemapEntry

```ruby
# app/models/sitemap_entry.rb
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
```

### View

```erb
<%# app/views/sitemap/show.xml.erb %>
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
<% @entries.each do |entry| %>
  <url>
    <loc><%= entry.loc %></loc>
    <lastmod><%= entry.lastmod_iso %></lastmod>
    <changefreq><%= entry.changefreq %></changefreq>
    <priority><%= entry.priority %></priority>
  </url>
<% end %>
</urlset>
```

---

## robots.txt Update

Update `/public/robots.txt` to reference the sitemap:

```
# See https://www.robotstxt.org/robotstxt.html for documentation

User-agent: *
Allow: /

# Sitemap
Sitemap: https://mbuzz.co/sitemap.xml

# Disallow authenticated/private routes
Disallow: /dashboard/
Disallow: /api/
Disallow: /login
Disallow: /signup
Disallow: /onboarding/
Disallow: /account/
Disallow: /admin/
Disallow: /users/

# Allow demo for indexing
Allow: /demo/dashboard
```

---

## Footer Link

Add sitemap link to the Legal section of the footer:

```erb
<%# app/views/layouts/_footer.html.erb %>
<div>
  <h4 class="text-xs font-semibold text-gray-900 uppercase tracking-wider mb-4">Legal</h4>
  <ul class="space-y-2">
    <li><%= link_to "Privacy Policy", privacy_path, class: "text-sm text-gray-600 hover:text-gray-900" %></li>
    <li><%= link_to "Terms of Service", terms_path, class: "text-sm text-gray-600 hover:text-gray-900" %></li>
    <li><%= link_to "Cookie Policy", cookies_path, class: "text-sm text-gray-600 hover:text-gray-900" %></li>
    <li><%= link_to "Sitemap", sitemap_path(format: :xml), class: "text-sm text-gray-600 hover:text-gray-900" %></li>
  </ul>
</div>
```

---

## AEO (AI Engine Optimization) Considerations

Modern AI crawlers (ChatGPT, Perplexity, Claude web search) use sitemaps to discover content. Additional optimizations:

### 1. Clean URL Structure

Already implemented with `/articles/:slug` pattern.

### 2. robots.txt AI Bot Directives

Consider explicit permissions for AI crawlers:

```
# AI Crawlers - Allow for discoverability
User-agent: GPTBot
Allow: /

User-agent: ChatGPT-User
Allow: /

User-agent: Claude-Web
Allow: /

User-agent: PerplexityBot
Allow: /

User-agent: Amazonbot
Allow: /
```

### 3. Structured Data (Already Implemented)

Articles already have:
- JSON-LD Article schema
- FAQ schema (when `aeo.faq` is present)
- Author schema

### 4. Content Metadata

The article frontmatter already supports AEO fields:

```yaml
aeo:
  target_query: "mta vs mmm"
  tldr: "Quick summary for featured snippets"
  key_takeaways:
    - "Takeaway 1"
  faq:
    - q: "Question?"
      a: "Answer"
```

---

## Caching Strategy

Cache the entire sitemap response for 1 hour (already included in controller):

```ruby
expires_in 1.hour, public: true
```

### Cache Invalidation

Since articles are file-based and loaded at boot, cache expiration (1 hour) is sufficient. No explicit invalidation needed.

---

## Testing

### Controller Test

```ruby
# test/controllers/sitemap_controller_test.rb
require "test_helper"

class SitemapControllerTest < ActionDispatch::IntegrationTest
  test "sitemap returns XML with correct content type" do
    get sitemap_path(format: :xml)

    assert_response :success
    assert_equal "application/xml; charset=utf-8", response.content_type
  end

  test "sitemap includes homepage" do
    get sitemap_path(format: :xml)

    assert_includes response.body, "<loc>#{root_url}</loc>"
    assert_includes response.body, "<priority>1.0</priority>"
  end

  test "sitemap includes academy" do
    get sitemap_path(format: :xml)

    assert_includes response.body, "<loc>#{academy_url}</loc>"
  end

  test "sitemap includes documentation pages" do
    get sitemap_path(format: :xml)

    assert_includes response.body, docs_url("getting-started")
  end

  test "sitemap includes published articles" do
    get sitemap_path(format: :xml)

    Articles::Repository.published.each do |article|
      assert_includes response.body, article_url(article.slug)
    end
  end

  test "sitemap excludes draft articles" do
    get sitemap_path(format: :xml)

    Articles::Repository.all.select { |a| a.status == "draft" }.each do |article|
      refute_includes response.body, article_url(article.slug)
    end
  end

  test "sitemap has valid XML structure" do
    get sitemap_path(format: :xml)

    doc = Nokogiri::XML(response.body)
    assert doc.errors.empty?, "Invalid XML: #{doc.errors.join(', ')}"
    assert_equal "urlset", doc.root.name
  end
end
```

### Service Test

```ruby
# test/services/sitemap/generator_service_test.rb
require "test_helper"

class Sitemap::GeneratorServiceTest < ActiveSupport::TestCase
  test "returns array of SitemapEntry objects" do
    entries = Sitemap::GeneratorService.call

    assert entries.all? { |e| e.is_a?(SitemapEntry) }
  end

  test "includes static pages" do
    entries = Sitemap::GeneratorService.call
    locs = entries.map(&:loc)

    assert locs.any? { |loc| loc.end_with?("/") }, "Missing homepage"
    assert locs.any? { |loc| loc.include?("/academy") }, "Missing academy"
    assert locs.any? { |loc| loc.include?("/about") }, "Missing about"
  end

  test "homepage has highest priority" do
    entries = Sitemap::GeneratorService.call
    homepage = entries.find { |e| e.loc.end_with?("/") }

    assert_equal 1.0, homepage.priority
  end

  test "includes documentation pages" do
    entries = Sitemap::GeneratorService.call
    locs = entries.map(&:loc)

    assert locs.any? { |loc| loc.include?("/docs/getting-started") }
    assert locs.any? { |loc| loc.include?("/docs/javascript-sdk") }
  end

  test "maps article priority to sitemap priority" do
    entries = Sitemap::GeneratorService.call

    # P0 articles should have priority 0.8
    p0_articles = Articles::Repository.published.select { |a| a.priority == "P0" }
    p0_articles.each do |article|
      entry = entries.find { |e| e.loc.include?(article.slug) }
      assert_equal 0.8, entry.priority if entry
    end
  end

  test "entries have valid lastmod dates" do
    entries = Sitemap::GeneratorService.call

    entries.each do |entry|
      assert_respond_to entry.lastmod, :to_date
      assert_match(/\d{4}-\d{2}-\d{2}/, entry.lastmod_iso)
    end
  end
end
```

---

## Implementation Checklist

### Phase 1: Core Sitemap

- [ ] Create `SitemapEntry` value object (`app/models/sitemap_entry.rb`)
- [ ] Create `Sitemap::GeneratorService` (`app/services/sitemap/generator_service.rb`)
- [ ] Create `SitemapController` (`app/controllers/sitemap_controller.rb`)
- [ ] Create view (`app/views/sitemap/show.xml.erb`)
- [ ] Add route: `get "sitemap", to: "sitemap#show", defaults: { format: :xml }`
- [ ] Write controller tests
- [ ] Write service tests

### Phase 2: robots.txt & Footer

- [ ] Update `/public/robots.txt` with sitemap reference and disallow rules
- [ ] Add AI crawler directives to robots.txt
- [ ] Add sitemap link to footer (Legal section)

### Phase 3: Validation & Deployment

- [ ] Validate sitemap XML with Google Search Console
- [ ] Submit sitemap to Google Search Console
- [ ] Submit sitemap to Bing Webmaster Tools
- [ ] Verify AI crawlers can access sitemap

---

## Files to Create

```
app/models/sitemap_entry.rb
app/controllers/sitemap_controller.rb
app/services/sitemap/generator_service.rb
app/views/sitemap/show.xml.erb
test/controllers/sitemap_controller_test.rb
test/services/sitemap/generator_service_test.rb
```

## Files to Modify

```
config/routes.rb                      # Add sitemap route
public/robots.txt                     # Add sitemap reference + disallow rules
app/views/layouts/_footer.html.erb    # Add sitemap link
```

---

## Future Enhancements

| Enhancement | Description | Priority |
|-------------|-------------|----------|
| **Sitemap Index** | If pages exceed 50,000, split into multiple sitemaps | Low |
| **Image Sitemap** | Add image tags for article hero images | Medium |
| **News Sitemap** | If articles become time-sensitive news content | Low |
| **Ping on Publish** | Notify Google/Bing when sitemap updates | Medium |
| **HTML Sitemap** | Human-readable sitemap page | Low |

---

## References

- [Google Sitemap Guidelines](https://developers.google.com/search/docs/crawling-indexing/sitemaps/overview)
- [Sitemaps Protocol](https://www.sitemaps.org/protocol.html)
- [robots.txt Specification](https://developers.google.com/search/docs/crawling-indexing/robots/robots_txt)
- [OpenAI GPTBot](https://platform.openai.com/docs/gptbot)
- [Perplexity Crawler](https://docs.perplexity.ai/docs/perplexitybot)
