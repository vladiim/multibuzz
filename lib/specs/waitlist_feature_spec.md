# Waitlist Feature Specification

## Overview

A waitlist signup form that collects user information before launch. Uses a generic form submission system built with Single Table Inheritance (STI) to support multiple form types in the future.

## Data Model

### FormSubmission (Base Model - STI)

Generic form submission model that supports multiple form types.

**Fields:**
- `type` (string, not null) - STI type (e.g., "WaitlistSubmission")
- `email` (string, not null) - User's email address
- `data` (jsonb, not null, default: {}) - Flexible storage for form-specific fields
- `status` (integer, not null, default: 0) - Enum: pending (0), contacted (1), completed (2), spam (3)
- `ip_address` (string) - IP address for spam prevention
- `user_agent` (text) - Browser/device information
- `created_at`, `updated_at` (timestamps)

**Indexes:**
- `type` - For querying by form type
- `email` - For lookups and duplicate detection
- `status` - For filtering by status
- `created_at` - For chronological queries

**Validations:**
- Email: required, valid format
- Type: required

**Concerns:**
- `FormSubmission::Validations` - Base validation rules
- `FormSubmission::Scopes` - Common query scopes

**Scopes:**
- `recent` - Order by created_at DESC
- `by_type(type)` - Filter by form type

### WaitlistSubmission (STI Child)

Specific implementation for waitlist signups.

**Virtual Attributes (via store_accessor):**
- `role` (string) - User's role
- `framework` (string) - Preferred framework
- `framework_other` (string) - Custom framework if "other" selected

**Constants:**
- `VALID_ROLES` = `["developer", "founder", "product_manager", "other"]`
- `VALID_FRAMEWORKS` = `["rails", "django", "laravel", "other"]`

**Validations:**
- Role: required, must be in VALID_ROLES
- Framework: required, must be in VALID_FRAMEWORKS
- Framework Other: required if framework == "other"

**Concerns:**
- `WaitlistSubmission::Validations` - Waitlist-specific validation rules

## Implementation Status

### ✅ Completed

- [x] Database schema design
- [x] FormSubmission base model with STI support
- [x] WaitlistSubmission model with validations
- [x] FormSubmission::Validations concern
- [x] FormSubmission::Scopes concern
- [x] WaitlistSubmission::Validations concern
- [x] Migration for form_submissions table
- [x] Comprehensive test coverage for FormSubmission
- [x] Comprehensive test coverage for WaitlistSubmission
- [x] Test fixtures for both models
- [x] All tests passing (17 tests, 49 assertions)

### ⏳ Todo

#### Routes
- [ ] Add `resources :waitlist, only: [:new, :create]` route
- [ ] Add thank you page route

#### Controller
- [ ] Create `WaitlistController` with `new` and `create` actions
- [ ] Capture IP address from `request.remote_ip`
- [ ] Capture user agent from `request.user_agent`
- [ ] Flash success message on successful submission
- [ ] Flash error messages on validation failure
- [ ] Redirect to thank you page on success
- [ ] Render form again with errors on failure

#### Views
- [ ] Create `app/views/waitlist/new.html.erb` - Main signup form
- [ ] Form fields:
  - Email (text input, required)
  - Role (radio buttons or select)
  - Framework (radio buttons or select)
  - Framework Other (text input, conditional display when framework == "other")
- [ ] Use consistent styling with docs layout
- [ ] Add client-side validation (optional)
- [ ] Show/hide framework_other field based on framework selection
- [ ] Create `app/views/waitlist/create.html.erb` - Thank you page

#### Homepage Integration
- [ ] Add "Join Waitlist" button to homepage
- [ ] Link to `/waitlist/new`
- [ ] Update "Get Started Free" button to point to waitlist
- [ ] Add waitlist CTA to navigation (optional)

#### Future Enhancements (Not MVP)
- [ ] Email confirmation/verification
- [ ] Admin interface to view submissions
- [ ] Export submissions to CSV
- [ ] Email notifications on new submissions
- [ ] Spam detection/prevention
- [ ] Rate limiting
- [ ] Referral tracking
- [ ] Position in waitlist counter

## File Structure

```
app/
├── models/
│   ├── form_submission.rb
│   ├── waitlist_submission.rb
│   └── concerns/
│       ├── form_submission/
│       │   ├── validations.rb
│       │   └── scopes.rb
│       └── waitlist_submission/
│           └── validations.rb
├── controllers/
│   └── waitlist_controller.rb (TODO)
└── views/
    └── waitlist/
        ├── new.html.erb (TODO)
        └── create.html.erb (TODO)

db/
└── migrate/
    └── 20251121015619_create_form_submissions.rb

test/
├── models/
│   ├── form_submission_test.rb
│   └── waitlist_submission_test.rb
├── fixtures/
│   └── form_submissions.yml
└── controllers/
    └── waitlist_controller_test.rb (TODO)
```

## Example Usage

```ruby
# Create a waitlist submission
submission = WaitlistSubmission.new(
  email: "user@example.com",
  role: "developer",
  framework: "rails"
)

if submission.save
  # Success
else
  # Show errors: submission.errors.full_messages
end

# Query submissions
WaitlistSubmission.recent.pending
WaitlistSubmission.where(role: "developer")
WaitlistSubmission.contacted.count

# Update status
submission.contacted!
submission.completed!
submission.spam!
```

## Testing

All model tests passing:
- FormSubmission: 9 tests covering validations, enums, scopes
- WaitlistSubmission: 8 tests covering role/framework validations, store_accessor

Run tests:
```bash
bin/rails test test/models/form_submission_test.rb test/models/waitlist_submission_test.rb
```

## Notes

- Uses Single Table Inheritance (STI) for extensibility
- JSONB column allows flexible schema per form type
- Easy to add new form types (ContactSubmission, DemoRequestSubmission, etc.)
- Status enum enables workflow tracking
- IP address and user agent captured for spam prevention
- Store accessor provides typed access to JSONB fields
- Comprehensive validations ensure data quality
