# Billing Interface & Navigation Polish Specification

**Status**: Draft
**Priority**: P0 (Required for launch)
**Created**: 2025-12-04

---

## Problem Statement

1. **No billing page**: Users can't view their plan, usage, or upgrade options
2. **Wrong email URLs**: Billing emails link to generic dashboard instead of billing page
3. **Homepage nav**: Signed-in users see "Login" instead of "Dashboard"
4. **Settings structure**: Current `/dashboard/settings` with tabs is clunky

---

## Solution

### New `/account` Namespace

Replace tabbed settings with dedicated pages under `/account`:

| Route | Controller#Action | Purpose |
|-------|-------------------|---------|
| `GET /account` | `account#show` | General settings (name, billing email) |
| `PATCH /account` | `account#update` | Update general settings |
| `GET /account/billing` | `account/billing#show` | Plan, usage, upgrade |
| `POST /account/billing/checkout` | `account/billing#checkout` | Start Stripe checkout |
| `GET /account/billing/portal` | `account/billing#portal` | Redirect to Stripe portal |
| `GET /account/billing/success` | `account/billing#success` | Post-checkout success |
| `GET /account/billing/cancel` | `account/billing#cancel` | Checkout cancelled |
| `GET /account/team` | `account/team#show` | Team members (placeholder) |
| `GET /account/api_keys` | `account/api_keys#index` | API key management |
| `POST /account/api_keys` | `account/api_keys#create` | Generate new key |
| `DELETE /account/api_keys/:id` | `account/api_keys#destroy` | Revoke key |

### Shared Navigation

All `/account/*` pages share a side nav:

```
┌──────────────────────────────────────────────────────────────────────┐
│ Account Settings                                                      │
├─────────────┬────────────────────────────────────────────────────────┤
│             │                                                         │
│  General    │  [Content for current page]                            │
│  Billing    │                                                         │
│  Team       │                                                         │
│  API Keys   │                                                         │
│             │                                                         │
└─────────────┴────────────────────────────────────────────────────────┘
```

---

## Routes

```ruby
# config/routes.rb

# Account settings (new namespace)
resource :account, only: [:show, :update], controller: "account" do
  namespace :account do
    resource :billing, only: [:show], controller: "billing" do
      post :checkout
      get :portal
      get :success
      get :cancel
    end
    resource :team, only: [:show], controller: "team"
    resources :api_keys, only: [:index, :create, :destroy]
  end
end
```

**Named routes**:
- `account_path` → `/account`
- `account_billing_path` → `/account/billing`
- `account_billing_checkout_path` → `/account/billing/checkout`
- `account_billing_portal_path` → `/account/billing/portal`
- `account_team_path` → `/account/team`
- `account_api_keys_path` → `/account/api_keys`

---

## Pages

### 1. General (`/account`)

```
┌─────────────────────────────────────────────────────────────────┐
│ General Settings                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│ Account Name                                                     │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Acme Inc                                                    │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ Account ID (read-only)                                          │
│ acct_abc123                                                      │
│                                                                  │
│ Billing Email                                                    │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ billing@acme.com                                            │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ [Save Changes]                                                   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 2. Billing (`/account/billing`)

```
┌─────────────────────────────────────────────────────────────────┐
│ Billing                                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Current Plan                                                │ │
│ │                                                             │ │
│ │ ┌─────────┐                                                 │ │
│ │ │ Starter │  $29/month              Status: Active ✓       │ │
│ │ └─────────┘                                                 │ │
│ │                                                             │ │
│ │ Next billing date: January 4, 2025                         │ │
│ │                                                             │ │
│ │ [Manage Subscription]  ← only if has_active_subscription?  │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Usage This Period                                           │ │
│ │                                                             │ │
│ │ 12,500 / 50,000 events                                     │ │
│ │ [████████░░░░░░░░░░░░░░░░░░░░] 25%                         │ │
│ │                                                             │ │
│ │ Dec 4 - Jan 4, 2025                                        │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ ┌─────────────────────────────────────────────────────────────┐ │
│ │ Available Plans           ← hide if on highest paid plan   │ │
│ │                                                             │ │
│ │ ┌───────────┐ ┌───────────┐ ┌───────────┐                  │ │
│ │ │ Starter   │ │ Growth    │ │ Pro       │                  │ │
│ │ │ $29/mo    │ │ $99/mo    │ │ $299/mo   │                  │ │
│ │ │ 50K evts  │ │ 250K evts │ │ 1M evts   │                  │ │
│ │ │ [Upgrade] │ │ [Upgrade] │ │ [Upgrade] │                  │ │
│ │ └───────────┘ └───────────┘ └───────────┘                  │ │
│ └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3. Team (`/account/team`)

```
┌─────────────────────────────────────────────────────────────────┐
│ Team Members                                                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│ Team member management coming soon.                             │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4. API Keys (`/account/api_keys`)

Existing functionality, moved from `/dashboard/settings?tab=api_keys`.

---

## Email URL Updates

| Email | Link To |
|-------|---------|
| payment_failed | `account_billing_url` |
| payment_succeeded | `account_billing_url` |
| events_locked | `account_billing_url` |
| subscription_cancelled | `account_billing_url` |
| free_until_expiring_soon | `account_billing_url` |
| free_until_expired | `account_billing_url` |
| usage_warning | `account_billing_url` |
| usage_limit_reached | `account_billing_url` |
| trial_ending_soon | `account_billing_url` |
| trial_expired | `account_billing_url` |
| events_unlocked | `dashboard_url` |
| subscription_created | `dashboard_url` |
| free_until_granted | `dashboard_url` |
| trial_started | `dashboard_url` |

---

## Homepage Nav Fix

**Signed out**:
```
Features  Docs  Login  [Start]
```

**Signed in**:
```
Features  Docs  [Dashboard]
```

---

## Migration Plan

1. Create new `/account` routes and controllers
2. Move API keys functionality from `Dashboard::ApiKeysController` to `Account::ApiKeysController`
3. Move billing functionality from `Dashboard::BillingController` to `Account::BillingController`
4. Update all email templates with new URLs
5. Update homepage nav
6. Add redirects from old routes → new routes
7. Remove old `/dashboard/settings` route after confirming no links

---

## Checklist

### Phase 1: Routes & Controllers
- [ ] Add `/account` routes
- [ ] Create `AccountController` (show, update)
- [ ] Create `Account::BillingController` (show, checkout, portal, success, cancel)
- [ ] Create `Account::TeamController` (show - placeholder)
- [ ] Create `Account::ApiKeysController` (index, create, destroy)

### Phase 2: Views
- [ ] Create shared account layout with side nav
- [ ] Create `account/show.html.erb` (general settings form)
- [ ] Create `account/billing/show.html.erb` (plan, usage, upgrade)
- [ ] Create `account/team/show.html.erb` (placeholder)
- [ ] Create `account/api_keys/index.html.erb` (moved from dashboard)

### Phase 3: Email URLs
- [ ] Update 10 email templates with `account_billing_url`

### Phase 4: Homepage Nav
- [ ] Conditional rendering for signed-in users

### Phase 5: Cleanup
- [ ] Add redirects from old `/dashboard/settings` routes
- [ ] Remove old settings controller/views

---

## Files

### New Files
- `app/controllers/account_controller.rb`
- `app/controllers/account/billing_controller.rb`
- `app/controllers/account/team_controller.rb`
- `app/controllers/account/api_keys_controller.rb`
- `app/views/account/show.html.erb`
- `app/views/account/billing/show.html.erb`
- `app/views/account/billing/success.html.erb`
- `app/views/account/team/show.html.erb`
- `app/views/account/api_keys/index.html.erb`
- `app/views/layouts/_account_nav.html.erb`

### Modified Files
- `config/routes.rb`
- `app/views/billing_mailer/*.html.erb` (10 files)
- `app/views/pages/home.html.erb`
- `app/views/layouts/_nav.html.erb` (add Account Settings link)

### Deprecated (redirect then remove)
- `app/controllers/dashboard/settings_controller.rb`
- `app/controllers/dashboard/billing_controller.rb`
- `app/views/dashboard/settings/*`
- `app/views/dashboard/billing/*`
