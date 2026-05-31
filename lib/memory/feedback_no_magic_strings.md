---
name: feedback-no-magic-strings
description: No magic strings or repeated literals in code. Extract to named SCREAMING_SNAKE constants and reference them.
metadata:
  type: feedback
---

Do not inline string (or numeric) literals that carry meaning or repeat. Define a named constant (`SCREAMING_SNAKE`, `.freeze` collections, grouped under `# --- Section ---` headers) once and reference it everywhere.

The user has corrected this **twice** in one session while building the operator engine and the custom-dimensions resolver:
- SQL fragments (`"ILIKE"`, `"~*"`, `"%"`, `" OR "`, `"?"`) → `Dashboard::Scopes::Operators::SQL_ILIKE`, `SQL_REGEX_CI`, `WILDCARD`, `SQL_OR`, `SQL_PLACEHOLDER`.
- Operator slugs (`"equals"`, `"contains"`, …) → `EQUALS`, `CONTAINS`, … and `MATCHABLE` built from them.
- match-field slugs and mode strings (`"campaign_name"`, `"account"`, `"campaign"`) → named constants on the owning model (`DimensionRule::CAMPAIGN_NAME`, `CustomDimension::ACCOUNT_MODE`), with derived lists/maps (`MATCH_FIELDS = ROW_ATTRIBUTES.keys`).

**Why:** repeated literals drift and read as sloppy. A single named constant is the source of truth, reused across the model, services, and validations (e.g. `DimensionRule::OPERATORS = Dashboard::Scopes::Operators::MATCHABLE`).

**How to apply:** before writing a literal that means something (an operator, a slug, a SQL token, a status, a mode, a key), define it as a constant in the most relevant class/module and reference it. Build arrays/maps from the constants, not from fresh literals. Derive dependent lists (`X.keys`) instead of repeating. Idiomatic attribute symbols (`:campaign_name` as a column reference) and user-facing validation messages are not the target — meaningful/repeated value literals are. Pairs with CLAUDE.md "Naming → Constants: SCREAMING_SNAKE, .freeze, module wrapping, section headers" and [[feedback_two_space_continuation_indent]] (don't align the constant `=` columns).
