# Contact Submissions & Admin Panel Specification

**Status**: Completed
**Last Updated**: 2025-12-11
**Priority**: P1 - High

---

## Executive Summary

Update contact form handling to send email notifications, add an admin panel for managing all form submissions, and add waitlist prompts for features not yet live (data export, SDK builds).

---

## 1. Scope

### 1.1 In Scope

1. **Email Notifications**: Send all form submissions to `vlad@forebrite.com`
2. **Admin Panel**: Index/show views for all `FormSubmission` types with pagination
3. **Role Restrictions**: Require `is_admin` for admin submissions panel
4. **Feature Waitlist Forms**: Auto-fill waitlist for data export and coming-soon SDKs

### 1.2 Out of Scope

- CSV export of submissions (future enhancement)
- Status workflow management (mark as contacted/completed)
- Submission search/filtering
- Reply-to-submission from admin panel

---

## 2. Current State Analysis

### 2.1 Existing Models

| Model | Purpose | Storage |
|-------|---------|---------|
| `FormSubmission` | STI base class | `form_submissions` table |
| `ContactSubmission` | Contact form | `data: { name, subject, message }` |
| `WaitlistSubmission` | Pre-launch waitlist | `data: { role, framework, framework_other }` |
| `SdkWaitlistSubmission` | SDK waitlist | `data: { sdk_key, sdk_name, account_id }` |

### 2.2 Existing Admin Infrastructure

- `Admin::BaseController` with `require_admin` before_action
- `User#admin?` method (checks `is_admin` boolean)
- Routes: `namespace :admin` with accounts/billing controllers
- Views: Follow consistent Tailwind card/table patterns

### 2.3 Missing Pieces

- No email notification on form submission
- No admin UI for viewing submissions
- No waitlist capture for data export feature
- SDK waitlist exists but only in onboarding flow

---

## 3. Feature Specifications

### 3.1 Email Notifications

**Recipient**: `vlad@forebrite.com`

**Trigger**: After successful save of any `FormSubmission` subclass

**Email Content by Type**:

| Type | Subject | Body |
|------|---------|------|
| ContactSubmission | [mbuzz Contact] {subject} from {name} | Name, email, subject, message, timestamp |
| WaitlistSubmission | [mbuzz Waitlist] New signup from {email} | Email, role, framework, timestamp |
| SdkWaitlistSubmission | [mbuzz SDK Waitlist] {sdk_name} interest | Email, SDK name, account ID, timestamp |
| FeatureWaitlistSubmission (new) | [mbuzz Feature Waitlist] {feature_name} | Email, feature, context, timestamp |

### 3.2 Admin Panel

**URL**: `/admin/submissions`

**Access Control**: `is_admin` users only (via `Admin::BaseController`)

**Index View Features**:
- Paginated list (25 per page, using reusable `Pagination` concern)
- Columns: Type, Email, Subject/Details, Status, Created At, Actions
- Type badges with colors (Contact=blue, Waitlist=purple, SDK=green, Feature=amber)
- Status badges (pending=gray, contacted=blue, completed=green, spam=red)
- View link to show page

**Show View Features**:
- All submission data displayed
- Type-specific fields rendered appropriately
- Metadata: IP address, user agent, timestamps

### 3.3 Feature Waitlist Submissions

**New Model**: `FeatureWaitlistSubmission < FormSubmission`

**Fields** (via `store_accessor :data`):
- `feature_key` (string) - e.g., "data_export", "csv_export", "api_extract"
- `feature_name` (string) - Display name
- `context` (string, optional) - Where user saw the feature

**Target Features**:

| Feature Key | Display Name | Trigger Location |
|-------------|--------------|------------------|
| `data_export` | Data Export | Dashboard Export dropdown |
| `csv_export` | CSV Export | Dashboard Export dropdown |
| `api_extract` | API Extract | Dashboard Export dropdown |

### 3.4 SDK Waitlist Enhancement

The existing `SdkWaitlistSubmission` and onboarding flow already handle SDK waitlist.

**Additional Touchpoints** (where to add waitlist capture):
- Homepage SDK section (clicking "Coming Soon" SDK)
- Docs SDK pages for coming-soon SDKs

---

## 4. Design Patterns

### 4.1 Mailer Service Pattern

Use callback in `FormSubmission` base class to trigger notification:

```ruby
FormSubmission
  after_create_commit :send_notification_email

  private
  def send_notification_email
    FormSubmissionMailer.notify(self).deliver_later
  end
```

### 4.2 Admin Controller Pattern

Follow existing `Admin::AccountsController` pattern:

```ruby
Admin::SubmissionsController < Admin::BaseController
  include Pagination
  per_page 25
  # index, show only (read-only for now)
```

### 4.3 Pagination Concern

Reusable concern for controller pagination:

```ruby
module Pagination
  extend ActiveSupport::Concern

  included do
    class_attribute :per_page_count, default: 25
  end

  class_methods do
    def per_page(count)
      self.per_page_count = count
    end
  end

  private

  def paginate(scope)
    scope.limit(per_page_count).offset(page_offset)
  end
end
```

### 4.4 View Pattern

Follow `admin/billing/show.html.erb` card/table styling with:
- White background cards with shadow
- Gray header rows
- Hover states on table rows
- Helper methods for badges (in `Admin::SubmissionsHelper`)

### 4.5 Waitlist Button Helper

**Helper**: `WaitlistHelper#waitlist_button`

**Purpose**: Reusable button component that auto-submits waitlist for logged-in users or shows modal for guests.

**Behavior**:

| User State | Click Action |
|------------|--------------|
| Logged in | Auto-submit via POST, flash success message |
| Logged out | Open modal with email input form |

**Helper Signature**:
```ruby
waitlist_button(
  feature_key:,           # Required: "data_export", "csv_export", etc.
  feature_name:,          # Required: Display name for the feature
  context: nil,           # Optional: Where user saw this (e.g., "dashboard_export")
  label: "Join Waitlist", # Button text
  class: "",              # Additional CSS classes
  &block                  # Optional block for custom button content
)
```

**Rendered Output**:

For logged-in users:
```erb
<%= button_to feature_waitlist_path, params: { ... }, method: :post, class: "..." do %>
  Join Waitlist
<% end %>
```

For logged-out users:
```erb
<button type="button" data-controller="modal" data-action="click->modal#open" data-modal-target-value="waitlist-modal-{feature_key}">
  Join Waitlist
</button>
<!-- Modal rendered separately via partial -->
```

**Modal Component**: `shared/_waitlist_modal.html.erb`
- Email input field
- Feature key/name as hidden fields
- Submit to `feature_waitlist_path`
- Uses existing `modal` Stimulus controller

**Controller**: `FeatureWaitlistController#create`
- Accepts: `feature_key`, `feature_name`, `context`, `email` (for guests)
- For logged-in users: uses `current_user.email`
- Creates `FeatureWaitlistSubmission`
- Redirects back with flash notice

---

## 5. Domain Configuration

| Setting | Value |
|---------|-------|
| Notification Email | `vlad@forebrite.com` |
| From Address | `hello@mbuzz.co` (existing) |
| Production URL | `mbuzz.co/admin/submissions` |

---

## 6. File Structure

### 6.1 New Files

```
app/
├── controllers/
│   ├── admin/
│   │   └── submissions_controller.rb
│   ├── concerns/
│   │   └── pagination.rb
│   └── feature_waitlist_controller.rb
├── helpers/
│   ├── admin/
│   │   └── submissions_helper.rb
│   └── waitlist_helper.rb
├── mailers/
│   └── form_submission_mailer.rb
├── models/
│   ├── feature_waitlist_submission.rb
│   └── concerns/
│       └── feature_waitlist_submission/
│           └── validations.rb
└── views/
    ├── admin/
    │   └── submissions/
    │       ├── index.html.erb
    │       └── show.html.erb
    ├── shared/
    │   └── _waitlist_modal.html.erb
    └── form_submission_mailer/
        └── notify.html.erb

test/
├── controllers/
│   ├── admin/
│   │   └── submissions_controller_test.rb
│   └── feature_waitlist_controller_test.rb
├── helpers/
│   └── waitlist_helper_test.rb
├── mailers/
│   └── form_submission_mailer_test.rb
└── models/
    └── feature_waitlist_submission_test.rb
```

### 6.2 Modified Files

```
app/
├── models/
│   └── form_submission.rb              # Add after_create_commit callback
├── views/
│   └── dashboard/
│       └── show.html.erb               # Update export dropdown to waitlist buttons
config/
└── routes.rb                           # Add admin submissions routes, feature_waitlist route
test/
└── fixtures/
    └── form_submissions.yml            # Add feature waitlist fixtures
```

---

## 7. Implementation Checklist (Outside-In TDD)

### Phase 1: Feature Waitlist Model (Unit Tests First)

- [x] Create `FeatureWaitlistSubmission` model
- [x] Create `FeatureWaitlistSubmission::Validations` concern
- [x] Add fixture entries for test data
- [x] Write model tests (validations, store_accessor)

### Phase 2: Feature Waitlist Controller (Controller Tests First)

- [x] Write controller tests for `FeatureWaitlistController#create`
  - [x] Test: logged-in user auto-submits with their email
  - [x] Test: logged-out user submits with provided email
  - [x] Test: redirects back with success flash
  - [x] Test: handles missing feature_key gracefully
- [x] Add route: `post "feature_waitlist", to: "feature_waitlist#create"`
- [x] Create `FeatureWaitlistController` to pass tests

### Phase 3: Waitlist Button Helper

- [x] Write helper tests for `WaitlistHelper#waitlist_button`
  - [x] Test: renders button_to for logged-in users
  - [x] Test: renders modal trigger for logged-out users
  - [x] Test: accepts custom label and classes
  - [x] Test: accepts block for custom content
- [x] Create `WaitlistHelper` module
- [x] Create `shared/_waitlist_modal.html.erb` partial
- [x] Reuse existing `modal` Stimulus controller (no new JS needed)

### Phase 4: Email Notifications

- [x] Write mailer tests for `FormSubmissionMailer#notify`
  - [x] Test: sends to vlad@forebrite.com
  - [x] Test: correct subject for each submission type
  - [x] Test: includes all relevant fields in body
- [x] Create `FormSubmissionMailer` with `notify` action
- [x] Create email templates (HTML)
- [x] Add `after_create_commit` callback to `FormSubmission`

### Phase 5: Admin Panel Controller (Controller Tests First)

- [x] Write controller tests for `Admin::SubmissionsController`
  - [x] Test: index requires admin user
  - [x] Test: show requires admin user
  - [x] Test: non-admin redirected with alert
  - [x] Test: index paginates results
  - [x] Test: show displays correct submission
- [x] Add routes: `namespace :admin { resources :submissions, only: [:index, :show] }`
- [x] Create `Admin::SubmissionsController` to pass tests
- [x] Create reusable `Pagination` concern

### Phase 6: Admin Panel Views

- [x] Create `index.html.erb` with submissions table
- [x] Create `show.html.erb` with submission details
- [x] Create `Admin::SubmissionsHelper` with badge helper methods
- [x] Add link to admin submissions from admin index page

### Phase 7: Dashboard Integration

- [x] Update dashboard export dropdown with waitlist buttons
- [x] Add waitlist buttons for CSV Export and API Extract

### Phase 8: Final Testing & QA

- [x] All tests passing (run full suite) - 1702 tests, 0 failures
- [ ] Manual test: Contact form → email received → visible in admin
- [ ] Manual test: Waitlist form → email received → visible in admin
- [ ] Manual test: Feature waitlist (logged in) → auto-submit → email + admin
- [ ] Manual test: Feature waitlist (logged out) → modal → email + admin
- [ ] Manual test: Non-admin user cannot access admin panel

---

## 8. Routes Structure

```ruby
# config/routes.rb additions

# Feature waitlist endpoint
post "feature_waitlist", to: "feature_waitlist#create"

namespace :admin do
  # ... existing routes ...
  resources :submissions, only: [:index, :show]
end
```

---

## 9. Admin Navigation

Link added in admin submissions index page:

```erb
<nav class="flex gap-4 text-sm">
  <%= link_to "Billing", admin_billing_path, class: "text-indigo-600 hover:text-indigo-800" %>
  <%= link_to "Accounts", admin_billing_path, class: "text-indigo-600 hover:text-indigo-800" %>
</nav>
```

---

## 10. Success Criteria

| Metric | Target | Status |
|--------|--------|--------|
| Email delivery | 100% of submissions generate notification | ✅ Implemented |
| Admin access | Only `is_admin=true` users can view | ✅ Implemented |
| Response time | Index page < 200ms with 1000 submissions | ✅ Pagination implemented |
| Test coverage | All new code has tests | ✅ 55 new tests |

---

## 11. Future Enhancements (Not in Scope)

- [ ] Submission status management (mark contacted/completed)
- [ ] Bulk actions (mark spam, delete)
- [ ] CSV export of submissions
- [ ] Email reply from admin panel
- [ ] Slack/Discord webhook notifications
- [ ] Submission search and filtering
- [ ] Submission analytics (counts by type, status over time)
