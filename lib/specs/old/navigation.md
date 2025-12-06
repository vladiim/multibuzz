# Navigation Specification

**Status**: Complete
**Last Updated**: 2025-12-02

## Overview

Unified navigation system across all pages. Single shared partial ensures consistency and reduces code duplication.

---

## Design Principles

1. **Single source of truth** - One nav partial, conditionally rendered based on auth state
2. **Account-level vs User-level** - Clear separation of workspace and personal settings
3. **Minimal cognitive load** - No redundant tabs, logo click = home/dashboard
4. **Actionable dropdowns** - Each dropdown has clear purpose

---

## Navigation States

### Signed Out
```
┌─────────────────────────────────────────────────────────────────┐
│ 🔷 mbuzz                                    Docs  Login  Start  │
└─────────────────────────────────────────────────────────────────┘
     │
     └→ / (home)
```

### Signed In
```
┌─────────────────────────────────────────────────────────────────┐
│ 🔷 mbuzz                                    [Acme Inc ▼] [👤 ▼] │
└─────────────────────────────────────────────────────────────────┘
     │                                              │         │
     └→ /dashboard                                  │         │
                                                    │         │
                                    ┌───────────────┘         │
                                    │ ✓ Acme Inc              │
                                    │   Other Corp            │
                                    │   Side Project          │
                                    │ ─────────────────       │
                                    │ + Create Account        │
                                    │ ─────────────────       │
                                    │ ⚙ Account Settings      │
                                    └─────────────────────────┘
                                                              │
                                              ┌───────────────┘
                                              │ john@acme.com
                                              │ ─────────────
                                              │ Logout
                                              └───────────────
```

---

## Components

### Logo
- **Signed out**: Links to `/` (home)
- **Signed in**: Links to `/dashboard`
- Always shows "mbuzz" text

### Account Dropdown (Signed in only)
- **Header**: Current account name with checkmark
- **Account list**: Other accounts user belongs to (click to switch)
- **Divider**
- **Create Account**: Link to account creation (disabled, future)
- **Divider**
- **Account Settings**: Link to `/dashboard/settings`
  - API Keys tab
  - Team Members tab (placeholder)

### User Dropdown (Signed in only)
- **Header**: User email (non-clickable, informational)
- **Divider**
- **Logout**: Signs out user

### Public Links (Signed out only)
- **Docs**: Link to documentation
- **Login**: Link to login page
- **Get Started**: Link to waitlist/signup

---

## Implementation

### Architecture

Uses Rails `Current` attributes for thread-safe request context:

```ruby
# app/models/current.rb
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :account
end

# app/controllers/concerns/set_current_attributes.rb
# Sets Current.user and Current.account from session
# Provides helper methods: current_user, current_account, logged_in?
```

### Files

#### Core
- [x] `app/models/current.rb` - Thread-safe current attributes
- [x] `app/controllers/concerns/set_current_attributes.rb` - Sets Current from session
- [x] `app/controllers/application_controller.rb` - Includes SetCurrentAttributes

#### Shared Partial
- [x] `app/views/layouts/_nav.html.erb` - Unified nav with auth states

#### Pages Using Nav
- [x] `app/views/dashboard/show.html.erb` - Uses shared partial
- [x] `app/views/dashboard/api_keys/show_key.html.erb` - Uses shared partial
- [x] `app/views/dashboard/settings/show.html.erb` - Uses shared partial
- [x] `app/views/layouts/docs.html.erb` - Uses shared partial with docs sub-nav

#### Routes
- [x] `GET /dashboard/settings` → `Dashboard::SettingsController#show`
- [x] `GET /dashboard/api_keys` → Redirects to `/dashboard/settings?tab=api_keys`

#### Controllers
- [x] `Dashboard::SettingsController` - Account settings with tabs
- [x] `Dashboard::ApiKeysController` - Updated to redirect to settings

### Checklist

#### Phase 1: Unified Nav Partial
- [x] Update `_nav.html.erb` with signed-in/signed-out states
- [x] Account dropdown:
  - [x] Current account (checkmark)
  - [x] Other accounts (switchable)
  - [x] Create Account link (disabled for now)
  - [x] Account Settings link
- [x] User dropdown:
  - [x] Email header
  - [x] Logout button
- [x] Update `dashboard/show.html.erb` to use partial (remove inline nav)
- [x] Update `dashboard/api_keys/show_key.html.erb` to use partial
- [x] Update `layouts/docs.html.erb` to use partial
- [x] Remove "Dashboard | API Keys" top tabs from all pages

#### Phase 2: Account Settings Page
- [x] Create `Dashboard::SettingsController`
- [x] Create `/dashboard/settings` route
- [x] Create settings page with tabs:
  - [x] API Keys tab (move existing functionality)
  - [x] Team Members tab (placeholder)
- [x] Redirect `/dashboard/api_keys` → `/dashboard/settings?tab=api_keys`

#### Tests
- [x] All 550 tests passing
- [x] Nav renders correctly when signed out
- [x] Nav renders correctly when signed in
- [x] Account switching works via URL param
- [x] Settings page loads
- [x] API keys functionality preserved

---

## Future Enhancements

- Profile settings in user dropdown
- Change password
- Theme toggle (dark mode)
- Notification preferences
- Account creation flow
- Team member invitations
- Billing integration
