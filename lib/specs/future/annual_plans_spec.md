# Annual Plans

**Date:** 2026-05-19
**Status:** Draft (planned, not scheduled)
**Branch:** `feat/annual-plans`

## Problem

mbuzz bills monthly only. The pricing page FAQ (`app/views/pages/pricing.html.erb:109-114`) answers "Not yet" to annual plans. Annual prepay materially reduces churn (industry benchmark: ~2.4% annual vs ~7% monthly) and pulls a year of cash forward.

This was originally scoped alongside the Guided Setup service. It was split out when the Guided Setup offer settled on a **$1,500 credit-pack** model (see `guided_setup_service_spec.md`) that works on the existing monthly plans and does not require annual billing. Annual plans remain worth doing on their own merits — hence this standalone spec.

## Solution

Add a billing **interval** to the existing plan structure (no new plan rows):

- `plans` gains `annual_price_cents` and `stripe_annual_price_id`.
- `accounts` gains `billing_interval` — enum `{ monthly: 0, annual: 1 }`.
- Annual price = monthly × 10 — **two months free (~16.7%)**, the SaaS-median discount. Starter $290, Growth $990, Pro $2,990.
- Each Stripe Product gains a second recurring Price (interval `year`); IDs in Rails credentials, read by `db/seeds.rb`.
- `Billing::CheckoutService` accepts `interval:` and selects the monthly or annual price.
- The webhook handlers (`checkout_completed`, `subscription_updated`) set `billing_interval`.
- Pricing page gets a monthly/annual toggle; the "annual? Not yet" FAQ is rewritten; schema.org `Offers` updated.

A Guided Setup credit can be applied to an annual plan once this ships — no extra work; the Stripe customer credit balance draws down annual invoices the same as monthly.

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Discount size | Two months free (~16.7%) | SaaS median; intuitive "12 for the price of 10" framing |
| Scope | All paid tiers (Starter/Growth/Pro) | Annual is a real pricing feature, not a one-tier bolt-on |
| Modeling | Interval on existing plans | Avoids duplicate `*_annual` plan rows |
| Overage | Stays monthly | Annual covers the base subscription; metered overage bills monthly as today |

## Acceptance Criteria

- [ ] A customer can choose monthly or annual at checkout and is billed the correct amount
- [ ] `billing_interval` reflects the active subscription, kept in sync by webhooks
- [ ] Annual price equals monthly × 10 for every paid tier
- [ ] The pricing page toggles between monthly and annual prices and shows the saving
- [ ] Event limits and metered overage are unchanged for annual customers

## Out of Scope

- Multi-year terms
- Mid-cycle monthly↔annual proration beyond Stripe's default
- Per-tier discount variation
