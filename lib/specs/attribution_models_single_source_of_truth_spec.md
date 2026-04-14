# Attribution Models — Single Source of Truth for Marketing Copy

**Date**: 2026-04-14
**Priority**: P2 (copy bug, not a product bug, but causes real positioning drift)
**Status**: Draft
**Branch**: TBD

---

## Summary

The marketing site references the attribution model count and the list of model names in at least three places, all hardcoded, and all currently disagree with each other and with the authoritative constant in code. The authoritative source is `AttributionAlgorithms::IMPLEMENTED` (8 models). The homepage features block, the AML editor section header, and the positioning doc at `memory/long_term/positioning.md` (in `mbuzz-org`) have been drifting independently.

This spec replaces every hardcoded count/list on the public marketing site with calls to a helper that reads from `AttributionAlgorithms::IMPLEMENTED`, so the next time a model is added, renamed, or removed in code, the marketing site updates automatically on redeploy.

---

## Current State

### The authoritative source

`app/constants/attribution_algorithms.rb` defines:

```ruby
HEURISTIC = [
  FIRST_TOUCH,    # "first_touch"
  LAST_TOUCH,     # "last_touch"
  LINEAR,         # "linear"
  TIME_DECAY,     # "time_decay"
  U_SHAPED,       # "u_shaped"
  PARTICIPATION   # "participation"
].freeze

PROBABILISTIC = [
  MARKOV_CHAIN,   # "markov_chain"
  SHAPLEY_VALUE   # "shapley_value"
].freeze

IMPLEMENTED = (HEURISTIC + PROBABILISTIC).freeze  # 8 models total
```

**Count: 8. Named list (in order):** First touch, Last touch, Linear, Time decay, U-shaped, Participation, Markov chain, Shapley value.

### Places currently hardcoded (all drifting)

| Location | Current value | Should be |
|---|---|---|
| `config/locales/en.yml` → `pages.home.features.dark_funnel.title` | `"8 Attribution Models"` (just fixed from `"7"` in commit `8db0ce0`, Tue Apr 14 22:18) | `%{count}` interpolated from helper |
| `config/locales/en.yml` → `pages.home.features.dark_funnel.description` | `"First-touch, last-touch, linear, time-decay, position-based, Markov chain, Shapley value, and data-driven — all running on the same data..."` — **WRONG NAMES**: "position-based" should be "U-shaped", "data-driven" is not a model, "participation" is missing | `%{list}` interpolated from helper |
| `app/views/pages/home/_aml_editor.html.erb:6` | `"Choose from 6 built-in models. Customize the rules. Or create your own from scratch."` — **COUNT DISAGREES WITH LOCALE** | `<%= attribution_models_count %> built-in models` |
| `app/views/pages/home/_aml_editor.html.erb` tab list | Hardcoded 5 tabs (First Touch / Last Touch / Linear / Time Decay / U-Shaped) + Custom tab | Either render tabs from `AttributionAlgorithms::IMPLEMENTED` or document why only a subset is shown in UI. See **Open Questions** below. |
| `app/views/pages/pricing.html.erb` schema.org JSON-LD | `"Full access to all 8 attribution models"` (hardcoded string, no count) | Low priority — acceptable as literal text |
| `app/views/pages/home.html.erb` schema.org `featureList` | `"8 attribution models built-in"` hardcoded | Low priority — acceptable as literal text |

**Downstream:** `memory/long_term/positioning.md` (in the `mbuzz-org` repo, not this repo) also has a wrong list — it says "position-based" and "data-driven." That file is the copywriting source of truth for every directory listing, guest post, and ad. It will be fixed in a separate cascade commit in `mbuzz-org`, but this spec should be linked from there so the two repos stay in sync.

**Live directory listings already published with wrong names:** Crunchbase, G2 (pending), Capterra (in review), SaaSHub (in review) — all have "position-based" and "data-driven" in the long descriptions. These need a manual edit pass once the positioning doc is corrected. Tracked in `data/cron_log.csv` (add item as part of shipping this spec).

---

## Why This Matters

The drift is a symptom, not the disease. Every time we claim a model count in marketing copy, a human types a number. Humans lose count, forget the constant exists, or paste old copy from a competitor analysis. The fix is to make the claim uncopyable — thread the count/list through a helper so the template can't lie about it.

It also surfaces a real positioning-doc bug (wrong model names in both `memory/long_term/positioning.md` and every directory listing). The fix for THAT is a separate cascade commit in `mbuzz-org`, but shipping this spec is the forcing function — once the site reads from the constant, the positioning doc is the only remaining manual copy, and it gets updated once, for good.

---

## Proposed Implementation

### 1. Helper methods

Add to `app/helpers/application_helper.rb`:

```ruby
# Canonical attribution model metadata for the marketing site.
# Reads from AttributionAlgorithms::IMPLEMENTED so the homepage,
# pricing page, and any landing page stay in sync with the code.
def attribution_models_count
  AttributionAlgorithms::IMPLEMENTED.count
end

def attribution_models_display_list
  AttributionAlgorithms::IMPLEMENTED
    .map { |slug| attribution_model_display_name(slug) }
    .join(", ")
end

def attribution_model_display_name(slug)
  # Human-readable names for marketing copy. Keep this mapping in sync
  # with AttributionAlgorithms constants. Having a small explicit map
  # is safer than relying on `.humanize` — it prevents "shapley_value"
  # from becoming "Shapley value" (lowercase v) which reads wrong.
  case slug
  when AttributionAlgorithms::FIRST_TOUCH   then "first-touch"
  when AttributionAlgorithms::LAST_TOUCH    then "last-touch"
  when AttributionAlgorithms::LINEAR        then "linear"
  when AttributionAlgorithms::TIME_DECAY    then "time-decay"
  when AttributionAlgorithms::U_SHAPED      then "U-shaped"
  when AttributionAlgorithms::PARTICIPATION then "participation"
  when AttributionAlgorithms::MARKOV_CHAIN  then "Markov chain"
  when AttributionAlgorithms::SHAPLEY_VALUE then "Shapley value"
  else slug.humanize
  end
end
```

Unit tests:
- Count matches `IMPLEMENTED.length`
- Each slug in `IMPLEMENTED` has an explicit display name (fail test when a new model is added and its display name is missed — forces the update)
- Display list is comma-separated
- No trailing period (period belongs in the sentence template, not the helper)

### 2. Locale updates

```yaml
# config/locales/en.yml
pages:
  home:
    features:
      dark_funnel:
        title: "%{count} Attribution Models"
        description: "%{list} — all running on the same data, side by side, so you can see the spread between them."
```

### 3. View updates

`app/views/pages/home/_features.html.erb`:

```erb
<h3 class="feature__title">
  <%= t('pages.home.features.dark_funnel.title',
        count: attribution_models_count) %>
</h3>
<p class="feature__description">
  <%= t('pages.home.features.dark_funnel.description',
        list: attribution_models_display_list) %>
</p>
```

`app/views/pages/home/_aml_editor.html.erb`:

```erb
<p class="mt-4 text-xl text-gray-600 scroll-animate" data-controller="scroll-reveal">
  Choose from <%= attribution_models_count %> built-in models. Customize the rules. Or create your own from scratch.
</p>
```

### 4. AML editor tab list (see Open Questions)

Currently the tab UI shows a hand-picked subset of 5 built-in models + a "Custom" tab, even though the product has 8. There are two reasonable answers:

**A. Render all 8 tabs from the constant** — honest, auto-updates, but may overflow on mobile and requires icon mapping per model.

**B. Keep the hand-picked subset** — but add a data attribute or comment explaining it's intentionally a curated preview, and add a "see all 8 models →" link that scrolls to `#features` or links to `/docs/attribution-models`.

Pick one in discussion before implementing. Option A is more consistent with the single-source principle of this spec; option B is more pragmatic for marketing readability.

### 5. Sanity test

RSpec request spec that asserts the homepage body contains both:
- `"#{AttributionAlgorithms::IMPLEMENTED.count} Attribution Models"`
- All 8 display names in the description

This test fails the instant the constant changes and copy drifts.

---

## Out of Scope

- **Product dashboard copy.** This spec covers marketing pages only. The in-app attribution model picker reads from the constant directly today and is correct.
- **DSL documentation.** Rewriting `/docs/dsl` and the `/docs/attribution-models` pages to use the same helper is a follow-up — low priority since those pages already list models by name and don't repeat counts.
- **`mbuzz-org/memory/long_term/positioning.md` correction.** Tracked in a separate mbuzz-org commit once this spec ships. Link from there back to this spec.
- **Cleaning up already-published directory listings** (Crunchbase, G2, Capterra, SaaSHub) with the wrong model names. Tracked in a new cron item, will be a manual edit pass once the positioning doc is fixed.

---

## Open Questions

1. **Tab list: all 8 or curated 5?** (see Section 4 above)
2. **Display name for `participation` and `u_shaped`** — are these the terms customers recognise? Should they be "U-shaped (position-based)" for SEO match with competitor terminology? Check GA4 / Dreamdata / HockeyStack language before finalising.
3. **Schema.org `featureList` on `home.html.erb`** — keep as hardcoded `"8 attribution models built-in"` or drive from helper? Trade-off is that schema.org blocks are in `content_for :head` which has helper access but many devs don't expect to see logic there.

---

## Success Criteria

- Homepage `/` renders "8 Attribution Models" in the features block with all 8 display names in the description
- AML editor subtitle renders "8 built-in models" (or whatever `IMPLEMENTED.count` is at deploy time)
- Adding a new algorithm to `AttributionAlgorithms::IMPLEMENTED` + its display name in `attribution_model_display_name` is the ONLY change needed to update the marketing site's model count and list — no locale edits, no view edits, no hunting through ERB files
- RSpec test passes on current code, and would fail if someone hardcodes "9" anywhere in the features section
- No new drift opportunities introduced (specifically, no new hardcoded counts elsewhere in the codebase)

---

## Related

- `config/locales/en.yml` — `pages.home.features.dark_funnel.title` (most recent fix: commit `8db0ce0`, 2026-04-14 22:18 +1000)
- `app/constants/attribution_algorithms.rb` — the single source of truth for model slugs
- `app/views/pages/home/_features.html.erb` — features grid consuming the locale
- `app/views/pages/home/_aml_editor.html.erb` — separate copy block drifting independently
- `mbuzz-org/memory/long_term/positioning.md` — positioning doc in the sibling repo, also wrong today, needs cascade fix after this ships
- `mbuzz-org/lib/specs/artifacts/backlink_wedge1/directory_submission_pack.md` — lists the live directory listings that will need manual edits
