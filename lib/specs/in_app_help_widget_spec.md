# In-App Help Widget

**Date:** 2026-03-12
**Status:** Draft
**Branch:** `feature/in-app-help-widget`

## Problem

Logged-in users have no way to ask for help without leaving the app. The public contact form at `/contact` lacks context — we don't know which page they were on, which account they're using, or who they are. Every support interaction starts with "what's your email?" and "can you send a screenshot?"

## Current State

- Public contact form exists at `/contact` (`ContactsController`, `ContactSubmission < FormSubmission`)
- `FormSubmission` STI base handles notification emails via `FormSubmissionMailer`, status tracking (`pending/contacted/completed/spam`), and admin view at `/admin/submissions`
- Mailer currently sends to `vlad@forebrite.com` — needs updating to `vlad@mbuzz.co`
- JSONB `data` column with `store_accessor` per subclass
- Authenticated layout renders `layouts/_nav.html.erb` on every page
- `modal_controller.js` exists for open/close/escape behavior
- `current_user`, `current_account`, `logged_in?` available in views

## Solution

A floating help icon (bottom-right corner) visible on every authenticated page. Clicking it opens a modal with a short form. On submit, contextual metadata is captured automatically — no user effort required.

### How It Works

```
User clicks help icon
  → Modal opens with message textarea + category select
  → User submits
  → Controller creates HelpSubmission with:
      - User-provided: message, category
      - Auto-captured: page_url, user prefix_id, account prefix_id,
        account name, user email, IP, user agent
  → FormSubmissionMailer fires to vlad@mbuzz.co (existing after_create_commit)
  → Modal shows success state, auto-closes after 3s
  → Submission appears in /admin/submissions with all context
```

### Key Files

| File | Purpose | Changes |
|------|---------|---------|
| `app/models/help_submission.rb` | STI subclass of `FormSubmission` | New |
| `app/models/concerns/help_submission/validations.rb` | Validations | New |
| `app/views/layouts/_help_widget.html.erb` | Floating icon + modal partial | New |
| `app/views/layouts/_nav.html.erb` | Render the widget partial | Add `render` call |
| `app/controllers/help_submissions_controller.rb` | Handle create | New |
| `config/routes.rb` | `POST /help` | Add route |
| `app/mailers/form_submission_mailer.rb` | Update recipient to `vlad@mbuzz.co` | Update |
| `app/helpers/admin/submissions_helper.rb` | Badge color for Help type | Update |
| `app/views/admin/submissions/show.html.erb` | Render help-specific fields | Update |
| `config/locales/en.yml` | Category labels | Update |

## Key Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| New STI subclass vs reuse `ContactSubmission` | New `HelpSubmission` | Different fields, different context. Keep STI clean. |
| Floating icon vs nav link | Floating icon (fixed bottom-right) | Always accessible regardless of scroll. Industry standard (Intercom, Crisp). |
| Stimulus controller | Reuse `modal_controller.js` | Already handles open/close/escape. No new JS needed. |
| Capture context server-side | Yes — controller reads `current_user`, `current_account`, referrer | User doesn't have to type it. More reliable than client-side. |
| Page URL capture | `request.referrer` in controller (form submits via Turbo) | Captures the page they were actually on, not the POST endpoint. |
| Success UX | Inline success message in modal, auto-close | No page redirect. Keeps user in context. |
| Notification email | `vlad@mbuzz.co` | All form submissions (including existing contact form) should use the mbuzz domain. |

## All States

| State | Condition | Expected Behavior |
|-------|-----------|-------------------|
| Happy path | Logged-in user submits valid form | Submission created, email sent to `vlad@mbuzz.co`, success message shown |
| Not logged in | `logged_in?` is false | Widget not rendered at all |
| Empty message | User submits without message | Validation error shown inline |
| Turbo submission | Form submits via Turbo Stream | Modal content replaced with success or errors — no page reload |
| Admin view | Admin views submission | Shows all contextual fields (page URL, user, account, category, message) |
| Rapid submission | User submits multiple times | Standard form behavior — each creates a submission. No rate limiting (V1). |

## Acceptance Criteria

- [ ] Floating help icon visible on every authenticated page (bottom-right, fixed position)
- [ ] Icon not visible when logged out
- [ ] Clicking icon opens modal with category select and message textarea
- [ ] Submitting with empty message shows validation error
- [ ] Successful submission captures: message, category, page_url, user email, user prefix_id, account prefix_id, account name, IP, user agent
- [ ] `FormSubmissionMailer` sends to `vlad@mbuzz.co` (update existing mailer — affects all form submissions)
- [ ] Submission appears in `/admin/submissions` with help-specific detail rendering
- [ ] Admin badge shows distinct color for Help type
- [ ] Modal shows success state after submission (no page redirect)
- [ ] Escape key closes the modal
- [ ] Clicking outside the modal closes it

## Implementation Details

### HelpSubmission Model

```ruby
class HelpSubmission < FormSubmission
  VALID_CATEGORIES = %w[bug question feature_request other].freeze

  store_accessor :data, :message, :category, :page_url,
                        :user_prefix_id, :account_prefix_id, :account_name

  include HelpSubmission::Validations
end
```

Validations: `message` presence, `category` inclusion.

### Categories

| Key | Label |
|-----|-------|
| `bug` | Bug Report |
| `question` | Question |
| `feature_request` | Feature Request |
| `other` | Other |

### Controller

```ruby
class HelpSubmissionsController < ApplicationController
  before_action :require_login

  def create
    @submission = HelpSubmission.new(help_params)
    # ... Turbo Stream response (success or errors)
  end

  private

  def help_params
    params.require(:help_submission).permit(:message, :category).merge(
      email: current_user.email,
      ip_address:onal_ip,
      user_agent: request.user_agent,
      data: {
        page_url: request.referrer,
        user_prefix_id: current_user.prefix_id,
        account_prefix_id: current_account.prefix_id,
        account_name: current_account.name
      }
    )
  end
end
```

### Mailer Update

Update `FormSubmissionMailer` recipient from `vlad@forebrite.com` to `vlad@mbuzz.co`. This applies to all `FormSubmission` subclasses (contact, waitlist, SDK waitlist, feature waitlist, integration requests, and the new help submissions).

### Widget Partial

Rendered inside `_nav.html.erb`, gated by `logged_in?`:

```erb
<% if logged_in? %>
  <%= render "layouts/help_widget" %>
<% end %>
```

Fixed-position button (bottom-right) + modal using `data-controller="modal"`.

## Out of Scope

- Live chat / real-time messaging
- Rate limiting / spam prevention (V1 — authenticated users only, low risk)
- File/screenshot attachments
- Ticket tracking or status updates for the submitter
- Knowledge base or FAQ suggestions
- Mobile-specific layout adjustments beyond responsive Tailwind
