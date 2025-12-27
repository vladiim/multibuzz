# Articles & Landing Pages: Technical Implementation Spec

**Status**: Design Standard
**Created**: 2025-12-27
**Related**: `lib/marketing/mta_academy_content_plan.md`

---

## Architecture Overview

File-based article system using `.md.erb` with YAML frontmatter. No database storage—articles parsed from disk at boot and cached in memory.

---

## Domain Model

### Core Entities

```
Article (Value Object)
├── slug: string (unique identifier, URL-safe)
├── frontmatter: ArticleFrontmatter (parsed YAML)
├── content: string (raw md.erb body)
├── file_path: string (absolute path to source file)
└── rendered_html: string (cached render output)

ArticleFrontmatter (Value Object)
├── metadata: ArticleMetadata
├── seo: SeoMetadata
├── aeo: AeoMetadata
├── schema: SchemaMetadata
├── taxonomy: TaxonomyMetadata
├── media: MediaMetadata
└── interactive: InteractiveMetadata

Section (Enum)
├── fundamentals
├── models
├── integration
├── funnel_forecasting
├── implementation
├── advanced
└── mbuzz
```

---

## File Structure

```
app/
├── content/
│   └── articles/
│       ├── fundamentals/
│       │   ├── what-is-multi-touch-attribution.md.erb
│       │   ├── mta-vs-mmm.md.erb
│       │   └── server-side-vs-client-side.md.erb
│       ├── models/
│       │   ├── first-touch-attribution.md.erb
│       │   ├── last-touch-attribution.md.erb
│       │   ├── linear-attribution.md.erb
│       │   ├── time-decay-attribution.md.erb
│       │   └── markov-chain-attribution.md.erb
│       ├── integration/
│       │   ├── mta-with-mmm.md.erb
│       │   └── incrementality-testing.md.erb
│       ├── funnel-forecasting/
│       │   ├── tiered-funnel-attribution.md.erb
│       │   └── bottom-up-revenue-forecast.md.erb
│       ├── implementation/
│       │   ├── lookback-window-optimization.md.erb
│       │   └── budget-reallocation.md.erb
│       ├── advanced/
│       │   └── shapley-value-attribution.md.erb
│       └── mbuzz/
│           ├── mbuzz-vs-ga4.md.erb
│           └── dsl-reference.md.erb
│
├── assets/
│   └── images/
│       └── articles/
│           ├── diagrams/           # SVG/PNG inline diagrams
│           ├── og/                 # Open Graph images (1200x630)
│           ├── screenshots/        # Dashboard screenshots
│           └── downloads/          # PDF templates, Excel files
│
├── models/
│   └── article.rb                  # PORO, not ActiveRecord
│
├── services/
│   └── articles/
│       ├── loader_service.rb       # Parse all articles from disk
│       ├── renderer_service.rb     # Render md.erb to HTML
│       ├── cache_service.rb        # Memory cache management
│       └── validator_service.rb    # Frontmatter validation
│
├── controllers/
│   └── articles_controller.rb
│
├── views/
│   ├── articles/
│   │   ├── show.html.erb
│   │   ├── index.html.erb          # Academy hub
│   │   └── _article_card.html.erb
│   └── layouts/
│       └── article.html.erb
│
└── helpers/
    └── articles_helper.rb          # Extends DocsHelper
```

---

## Frontmatter Schema

### Complete Field Reference

```yaml
---
# ═══════════════════════════════════════════════════════════════════
# REQUIRED METADATA
# ═══════════════════════════════════════════════════════════════════
title: "What is Multi-Touch Attribution?"
slug: "what-is-multi-touch-attribution"
description: "Multi-touch attribution assigns credit to all touchpoints..."
published_at: 2025-12-27
section: fundamentals
status: published                          # draft | review | published

# ═══════════════════════════════════════════════════════════════════
# SEO METADATA
# ═══════════════════════════════════════════════════════════════════
seo:
  title: "What is Multi-Touch Attribution? [2025 Guide]"
  canonical_url: null
  noindex: false

# ═══════════════════════════════════════════════════════════════════
# AEO (ANSWER ENGINE OPTIMIZATION)
# ═══════════════════════════════════════════════════════════════════
aeo:
  target_query: "what is multi touch attribution"
  monthly_search_volume: 2400
  snippet_target: "definition"             # definition | list | table | steps
  tldr: "Multi-touch attribution distributes conversion credit across..."
  key_takeaways:
    - "MTA credits all touchpoints, not just first or last"
    - "Rule-based models are transparent; data-driven need more data"
    - "Server-side tracking captures 30% more touchpoints"
  faq:
    - q: "What is the difference between MTA and last-touch?"
      a: "Last-touch credits only the final interaction..."
    - q: "How much data do I need for MTA?"
      a: "Start with at least 100 conversions per month..."

# ═══════════════════════════════════════════════════════════════════
# SCHEMA.ORG STRUCTURED DATA
# ═══════════════════════════════════════════════════════════════════
schema:
  type: Article                            # Article | HowTo | FAQPage
  author: mbuzz Team
  date_modified: null                      # Auto-set from file mtime

# ═══════════════════════════════════════════════════════════════════
# TAXONOMY & ORGANIZATION
# ═══════════════════════════════════════════════════════════════════
category: "Attribution Fundamentals"
tags: [multi-touch attribution, marketing measurement, analytics]
section_order: 1
priority: P0                               # P0 | P1 | P2 | P3
related_articles:
  - mta-vs-mmm
  - first-touch-attribution

# ═══════════════════════════════════════════════════════════════════
# MEDIA
# ═══════════════════════════════════════════════════════════════════
featured_image:
  path: articles/diagrams/mta-overview.svg
  alt: "Multi-touch attribution overview"
  caption: "How MTA distributes credit"
og_image: articles/og/what-is-mta.png

# ═══════════════════════════════════════════════════════════════════
# INTERACTIVE ELEMENTS
# ═══════════════════════════════════════════════════════════════════
has_code_examples: true
has_calculator: false
has_download: true
download:
  title: "Attribution Model Decision Tree"
  file: articles/downloads/decision-tree.pdf
  format: PDF
---
```

---

## Service Architecture

### Articles::LoaderService

**Purpose**: Parse all `.md.erb` files from content directory.

**Input**: None (reads from `Rails.root.join("app/content/articles")`).

**Output**: `Array<Article>` parsed value objects.

**Dependencies**: `FrontMatterParser` gem.

**Caching**: Results cached in `Rails.cache` with key `articles:all`.

**Invalidation**: On deploy (Kamal restarts containers).

---

### Articles::RendererService

**Purpose**: Render article content (md.erb → HTML).

**Input**: `Article` value object.

**Output**: HTML string with syntax highlighting, embedded helpers.

**Dependencies**: `Redcarpet`, `Rouge`, `ERB`.

**Pattern**: Uses existing `DocsHelper#render_markdown` and `SyntaxHighlightRenderer`.

**Context**: ERB context includes all `ArticlesHelper` methods.

---

### Articles::ValidatorService

**Purpose**: Validate frontmatter completeness and correctness.

**Input**: `Article` value object.

**Output**: `{ valid: boolean, errors: Array<String> }`.

**Rules**:
- Required fields present: `title`, `slug`, `description`, `published_at`, `section`
- `section` in allowed list
- `status` in `[draft, review, published]`
- `slug` matches filename
- `og_image` file exists if specified
- `related_articles` slugs exist

---

### Articles::CacheService

**Purpose**: Manage in-memory article cache.

**Operations**:
- `warm!` — Load all articles into cache at boot
- `invalidate!` — Clear cache (triggers reload)
- `get(slug)` — Retrieve single article
- `all` — Retrieve all articles

**Cache Backend**: `Rails.cache` (Solid Cache).

**Keys**:
- `articles:all` — Full article index
- `articles:rendered:{slug}` — Rendered HTML per article

---

## Image Storage

### Static Assets (Propshaft)

**Location**: `app/assets/images/articles/`

**Subdirectories**:

| Path | Purpose | Dimensions | Format |
|------|---------|------------|--------|
| `diagrams/` | Inline SVG/PNG diagrams | Variable | SVG preferred |
| `og/` | Open Graph social images | 1200×630 | PNG |
| `screenshots/` | Dashboard screenshots | 1600×900 max | PNG/WebP |
| `downloads/` | PDF/Excel downloads | N/A | PDF, XLSX |

**Naming Convention**: `{category}-{descriptor}.{ext}`

Examples:
- `diagrams/attribution-ladder.svg`
- `og/what-is-multi-touch-attribution.png`
- `downloads/budget-reallocation-template.xlsx`

**CDN**: Propshaft fingerprints assets for cache busting. CDN configured in `config/environments/production.rb`.

---

## Routes

```ruby
# config/routes.rb

# Academy hub
get "academy", to: "articles#index", as: :academy

# Section listing
get "academy/:section", to: "articles#section", as: :academy_section,
    constraints: { section: /fundamentals|models|integration|funnel-forecasting|implementation|advanced|mbuzz/ }

# Individual article
get "articles/:slug", to: "articles#show", as: :article

# Sitemap for articles
get "articles.xml", to: "articles#sitemap", as: :articles_sitemap, defaults: { format: :xml }

# Redirects
get "blog/:slug", to: redirect("/articles/%{slug}")
get "learn/:slug", to: redirect("/articles/%{slug}")
```

---

## URL Structure

| URL Pattern | Description |
|-------------|-------------|
| `/academy` | Hub page listing all sections |
| `/academy/fundamentals` | Section listing |
| `/articles/what-is-multi-touch-attribution` | Individual article |
| `/articles.xml` | Sitemap for crawlers |

---

## Meta Tags & Schema.org

### Head Tags (per article)

```html
<!-- Primary -->
<title>{seo.title} | mbuzz</title>
<meta name="description" content="{description}">
<link rel="canonical" href="https://mbuzz.co/articles/{slug}">

<!-- Open Graph -->
<meta property="og:type" content="article">
<meta property="og:title" content="{seo.title}">
<meta property="og:description" content="{description}">
<meta property="og:image" content="https://mbuzz.co/assets/{og_image}">
<meta property="og:url" content="https://mbuzz.co/articles/{slug}">
<meta property="article:published_time" content="{published_at}">
<meta property="article:modified_time" content="{date_modified}">
<meta property="article:author" content="{author}">
<meta property="article:section" content="{category}">
<meta property="article:tag" content="{tags}">

<!-- Twitter Card -->
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{seo.title}">
<meta name="twitter:description" content="{description}">
<meta name="twitter:image" content="https://mbuzz.co/assets/{og_image}">
```

### JSON-LD Structured Data

**Article Schema** (every article):
```json
{
  "@context": "https://schema.org",
  "@type": "Article",
  "headline": "{title}",
  "description": "{description}",
  "author": { "@type": "Organization", "name": "{author}" },
  "publisher": { "@type": "Organization", "name": "mbuzz", "logo": "..." },
  "datePublished": "{published_at}",
  "dateModified": "{date_modified}",
  "image": "{og_image_url}",
  "wordCount": "{word_count}",
  "keywords": "{tags}",
  "articleSection": "{category}"
}
```

**FAQPage Schema** (if FAQ exists):
```json
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    { "@type": "Question", "name": "...", "acceptedAnswer": { "@type": "Answer", "text": "..." } }
  ]
}
```

**HowTo Schema** (for implementation articles):
```json
{
  "@context": "https://schema.org",
  "@type": "HowTo",
  "name": "{title}",
  "description": "{description}",
  "step": [...]
}
```

---

## ERB Helpers for Content

### Available in md.erb Files

| Helper | Purpose |
|--------|---------|
| `render_tldr(text)` | Blue highlighted TL;DR box |
| `render_key_takeaways(array)` | Checkmark list of takeaways |
| `render_faq(array)` | Collapsible FAQ accordion |
| `render_info_box { }` | Blue info callout |
| `render_warning_box { }` | Amber warning callout |
| `render_diagram(path, alt:, caption:)` | Figure with caption |
| `render_related_articles(slugs)` | Related article links |
| `render_download(download_hash)` | Download CTA button |
| `code_tabs(examples, default:)` | Multi-language code tabs (from DocsHelper) |
| `render_markdown(text)` | Inline markdown rendering |

---

## Gem Dependencies

```ruby
# Gemfile additions

# Frontmatter parsing for articles
gem "front_matter_parser", "~> 1.0"
```

---

## Development Rake Tasks

```
rails articles:list          # List all articles with status
rails articles:validate      # Validate all frontmatter
rails articles:reload        # Clear cache and reload
rails articles:render[slug]  # Preview rendered HTML for slug
rails articles:new[slug]     # Generate new article from template
```

---

## Caching Strategy

### Boot-time Loading

```ruby
# config/initializers/articles.rb
Rails.application.config.after_initialize do
  Articles::CacheService.warm! unless Rails.env.test?
end
```

### Cache Keys

| Key | TTL | Content |
|-----|-----|---------|
| `articles:all` | ∞ (until redeploy) | Array of Article objects |
| `articles:index` | ∞ | Index by slug |
| `articles:rendered:{slug}` | ∞ | Rendered HTML string |

### Invalidation

- **On deploy**: Kamal restarts containers → initializer runs → cache warms
- **Manual**: `rails articles:reload` or `Articles::CacheService.invalidate!`

---

## Analytics Events

**Track via mbuzz (dogfooding)**:

| Event | Properties |
|-------|------------|
| `article_view` | `{ slug, section, category, reading_time }` |
| `article_scroll_depth` | `{ slug, depth: 25|50|75|100 }` |
| `article_download` | `{ slug, file_name, format }` |
| `article_cta_click` | `{ slug, cta_type, cta_text }` |

---

## Production URLs

| Resource | URL |
|----------|-----|
| Academy Hub | `https://mbuzz.co/academy` |
| Article | `https://mbuzz.co/articles/{slug}` |
| Section | `https://mbuzz.co/academy/{section}` |
| Sitemap | `https://mbuzz.co/articles.xml` |
| OG Images | `https://mbuzz.co/assets/articles/og/{slug}.png` |
| Downloads | `https://mbuzz.co/assets/articles/downloads/{file}` |

---

## Implementation Checklist

1. [ ] Add `front_matter_parser` to Gemfile
2. [ ] Create `app/content/articles/` directory structure
3. [ ] Create `app/assets/images/articles/` subdirectories
4. [ ] Implement `Article` value object
5. [ ] Implement `Articles::LoaderService`
6. [ ] Implement `Articles::RendererService`
7. [ ] Implement `Articles::CacheService`
8. [ ] Implement `Articles::ValidatorService`
9. [ ] Create `ArticlesController`
10. [ ] Create `article.html.erb` layout
11. [ ] Create `ArticlesHelper` (extend DocsHelper)
12. [ ] Add routes
13. [ ] Add Rake tasks
14. [ ] Write first P0 article
15. [ ] Configure analytics events
