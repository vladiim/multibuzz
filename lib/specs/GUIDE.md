# Specification Writing Guide

> How to write specs that ship features faster at Multibuzz

---

## Philosophy

A spec is a **thinking tool**, not a bureaucratic artifact. The act of writing is the act of design. If you can't explain the feature clearly in writing, you don't understand it well enough to build it.

**Principles:**

1. **Written by the builder** -- the person implementing writes the spec. Forces deep thinking.
2. **Short and opinionated** -- communicate intent and constraints, not implementation steps.
3. **Acceptance criteria become tests** -- every spec feeds directly into TDD.
4. **Updated when done** -- spec drift is tech debt. Update or archive.
5. **Stored in the repo** -- versioned, discoverable, reviewed alongside code.

---

## When to Write a Spec

| Change Type | Spec Required? | Format |
|-------------|---------------|--------|
| Bug fix (clear root cause) | No | Just fix it |
| Small feature (< 1 day) | No | Commit message is enough |
| Feature with unknowns | **Yes** | Mini Spec |
| Multi-phase feature | **Yes** | Full Spec |
| Architecture change | **Yes** | Full Spec |
| Investigation / incident | **Yes** | Investigation Report |

**Rule of thumb:** If you'd need to explain the approach to someone before building it, write a spec.

---

## Directory Structure

```
lib/specs/
  GUIDE.md              # This file
  *.md                  # Active specs (what we're working on next)
  future/               # Planned but not yet scheduled
  old/                  # Completed, archived for reference
  incidents/            # Post-mortems and investigation reports
  marketing/            # Content and positioning specs
```

**Keep the root clean.** Only specs for the current or next sprint live in `lib/specs/`. Move completed work to `old/` and unscheduled ideas to `future/`.

---

## Before Writing: Research First

A spec is only as good as the research behind it. **Never assume. Verify.**

### Discovery Checklist

- [ ] **Read the existing code** -- don't describe what you *think* it does
- [ ] **Run the feature locally** -- see current behavior firsthand
- [ ] **Check the tests** -- what's covered? What edge cases exist?
- [ ] **Search for patterns** -- how does the codebase already solve similar problems?
- [ ] **Map dependencies** -- what calls this code? What does it call?
- [ ] **Verify external systems** -- API responses, gem docs, third-party behavior
- [ ] **List unknowns** -- what you don't know and how you'll find out

### Every Claim Needs a Source

| Source | Examples | How to Verify |
|--------|----------|---------------|
| **The Code** | Model relationships, existing methods | Read files, run tests |
| **External Docs** | API responses, gem behavior | Check docs, make real calls |
| **Stakeholder** | Business rules, priorities | Ask, document the answer |

---

## Mini Spec (Most Features)

Five sections. One page. Enough to align and start building.

```markdown
# [Feature Name]

**Date:** YYYY-MM-DD
**Status:** Draft / Ready / In Progress / Complete
**Branch:** `feature/branch-name`

## Problem

[What's broken or missing? Who's affected? Why now?]

## Solution

[High-level approach. Reference existing patterns in the codebase.]

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| [Decision point] | [What we chose] | [Rationale] |

## Acceptance Criteria

- [ ] [Testable criterion 1]
- [ ] [Testable criterion 2]
- [ ] [Testable criterion 3]

## Out of Scope

- [What we're explicitly NOT doing]
```

---

## Full Spec (Complex Features)

Use when the feature spans multiple phases, touches many files, or has significant unknowns.

```markdown
# [Feature Name] Specification

**Date:** YYYY-MM-DD
**Priority:** P0 / P1 / P2
**Status:** Discovery / Draft / Ready / In Progress / Complete
**Branch:** `feature/branch-name`

---

## Summary

[One paragraph. Non-technical stakeholders should understand this.]

---

## Current State

[What exists today. Include file paths and relevant code references.]

### Data Flow (Current)

```
[Trace how data moves through the system today]
```

---

## Proposed Solution

[Architecture-level description. Reference existing patterns.]

### Data Flow (Proposed)

```
[How data will flow after changes]
```

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/services/...` | [Description] | [What changes] |

---

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Happy path | [condition] | [behavior] |
| Empty | `collection.empty?` | [empty state] |
| Error | `rescue => e` | [error handling] |
| Edge case | [condition] | [behavior] |

---

## Implementation Tasks

### Phase 1: [Name]

- [ ] **1.1** [Task]
- [ ] **1.2** [Task]
- [ ] **1.3** Write tests

### Phase 2: [Name]

- [ ] **2.1** [Task]
- [ ] **2.2** Write tests

---

## Testing Strategy

### Unit Tests

| Test | File | Verifies |
|------|------|----------|
| [Name] | `test/services/...` | [Behavior] |

### Manual QA

1. [Step]
2. [Step]
3. Verify [expected outcome]

---

## Definition of Done

- [ ] All tasks completed
- [ ] Tests pass (unit + integration)
- [ ] Manual QA on dev
- [ ] No regressions
- [ ] Spec updated with final state

---

## Out of Scope

[Explicit boundaries. What we're NOT doing.]
```

---

## Investigation Report (Incidents)

```markdown
# [Issue Name] Investigation

**Date:** YYYY-MM-DD
**Status:** Investigating / Resolved

## What Happened

[2-3 sentences: what broke, impact, resolution]

## Timeline

| Time | Event |
|------|-------|
| HH:MM | Issue reported |
| HH:MM | Root cause identified |
| HH:MM | Fix deployed |

## Root Cause

[Technical analysis with file paths and evidence]

## Fix Applied

[What changed and why]

## Prevention

[What prevents this from happening again]
```

---

## Writing Quality Checklist

### Good Specs

- Start with the problem, not the code
- Use domain language consistently (model names, service names as they appear in code)
- Document all states (happy path, empty, error, edge cases)
- Have testable acceptance criteria
- Reference existing codebase patterns
- Are proportional to the complexity of the work

### Bad Specs

| Anti-Pattern | Fix |
|--------------|-----|
| Walls of code | Describe interfaces, not implementations |
| Missing states | Table of all states with conditions |
| Vague criteria ("should be fast") | Measurable outcomes ("p95 < 200ms") |
| No testing plan | Acceptance criteria that map to tests |
| Assumptions without sources | Verify and cite |
| Spec-code drift | Update spec as part of "done" |

---

## Specs and TDD

Every spec should feed the development cycle:

```
1. Write spec (problem + acceptance criteria)
      |
2. Derive test cases from criteria (RED)
      |
3. Write minimal code to pass (GREEN)
      |
4. Run full test suite -- no regressions
      |
5. Refactor
      |
6. Update spec (check off tasks, note decisions)
      |
7. Commit: type(scope): description
```

**The bridge:** Acceptance criteria in the spec become test assertions. If a criterion can't be turned into a test, it's not specific enough.

---

## Multibuzz-Specific Conventions

### Always Consider

- **Multi-tenancy** -- every query scoped to account. Specs should note data isolation.
- **Server-side sessions** -- SDKs don't manage sessions. Specs touching visitor/session flow must respect this.
- **TimescaleDB** -- time-series queries use continuous aggregates in production but not in tests. Note this in specs that touch time-series data.
- **Solid Stack** -- no Redis. Cache, queue, and cable are all database-backed.
- **Minimise JavaScript** -- prefer Turbo Frames, Turbo Streams, and server-rendered HTML. When JS is needed, extend existing Stimulus controllers before creating new ones. Check `app/javascript/controllers/` for reusable controllers first.

### Frontend Decision Tree

```
Need interactivity?
  |
  +-- Can it be a page navigation? --> Use a link (Turbo Drive handles it)
  |
  +-- Can it update part of the page? --> Use Turbo Frame or Turbo Stream
  |
  +-- Need client-side behavior? --> Check existing Stimulus controllers
  |     |
  |     +-- Existing controller fits? --> Reuse it (add data attributes)
  |     +-- Existing controller close? --> Extend it (add a new action/target)
  |     +-- Nothing exists? --> Create a new Stimulus controller (last resort)
  |
  +-- Need a chart? --> Use Highcharts via existing chart controllers
```

**In specs:** When proposing UI interactions, note which approach you're using and why. If creating a new Stimulus controller, justify why existing ones can't be extended.

### Naming in Specs

Reference code artifacts by their actual names:

| Element | Convention | Example |
|---------|-----------|---------|
| Models | `Model::Name` | `Event::Conversion` |
| Services | `Module::ServiceName` | `Attribution::CreditService` |
| Controllers | Full class name | `Api::V1::EventsController` |
| Files | Relative path | `app/services/event/ingestion_service.rb` |

### Commit Messages

```
type(scope): description

Types: feat, fix, refactor, test, docs, chore
Scopes: auth, event, visitor, session, api, dashboard, export
```

---

## Lifecycle

1. **Write** -- create spec in `lib/specs/`
2. **Review** -- get feedback before building
3. **Build** -- implement following spec + TDD cycle
4. **Update** -- check off tasks, note any deviations
5. **Archive** -- move to `old/` when complete

Specs in `lib/specs/` should only be active work. If it's done, move it. If it's not scheduled, it belongs in `future/`.
