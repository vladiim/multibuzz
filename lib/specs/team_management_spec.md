# Team Management Specification

**Feature**: `/account/team` - Team member management with role-based access control
**Status**: Planned
**Priority**: E1S4

---

## Overview

Allow account owners and admins to invite team members, manage roles, and control access across the platform. Supports users belonging to multiple accounts.

---

## Roles & Permissions

### Role Hierarchy

| Role | Level | Description |
|------|-------|-------------|
| **Owner** | 3 | Full access. One per account. Cannot be deleted. |
| **Admin** | 2 | Manage team, billing, attribution models. Cannot transfer ownership. |
| **Member** | 1 | View-only dashboard access. Cannot modify settings. |
| **Viewer** | 0 | Reserved for future use (external stakeholders). |

### Permission Matrix

| Action | Owner | Admin | Member |
|--------|-------|-------|--------|
| View dashboard | ✓ | ✓ | ✓ |
| View attribution data | ✓ | ✓ | ✓ |
| Create/edit attribution models | ✓ | ✓ | ✗ |
| Manage conversion types | ✓ | ✓ | ✗ |
| Invite team members | ✓ | ✓ | ✗ |
| Remove team members | ✓ | ✓ | ✗ |
| Change member roles | ✓ | ✓* | ✗ |
| View/manage billing | ✓ | ✓ | ✗ |
| Manage API keys | ✓ | ✓ | ✗ |
| Transfer ownership | ✓ | ✗ | ✗ |
| Delete account | ✓ | ✗ | ✗ |

*Admins cannot promote to Owner or demote other Admins

---

## User Scenarios

### Scenario 1: New User Invitation

1. Admin enters email address on team page
2. System checks if email exists in users table
3. Email does NOT exist → create invitation token
4. Send invitation email with signup link + token
5. User clicks link → registration form (pre-filled email)
6. User completes registration
7. System creates User record
8. System updates AccountMembership status to `accepted`
9. User redirected to new account's dashboard

### Scenario 2: Existing User Invitation (Multi-Account)

**Critical Flow**: User already has an account elsewhere and is invited to join another account.

1. Admin enters email address on team page
2. System checks if email exists in users table
3. Email EXISTS → create AccountMembership with `pending` status
4. Send invitation email with accept/decline link + token
5. User clicks link → logged in or login prompt
6. Show invitation acceptance screen (account name, role offered)
7. User accepts → update membership status to `accepted`
8. User now has multiple accounts in their account switcher
9. User can switch between accounts via dropdown

**Multi-Account Considerations**:
- User maintains single login across all accounts
- Account switcher in header shows all accepted memberships
- Session tracks `current_account_id` separately from user
- Each account has independent data, roles, permissions
- User profile (name, email, password) is shared across accounts

### Scenario 3: Self-Registration with Invitation

1. New user signs up independently (creates their own account as Owner)
2. Later, receives invitation to join different account
3. Flow follows Scenario 2 (existing user)
4. User now owns Account A and is member of Account B

---

## Technical Architecture

### Domain Model

```
User (1) ----< AccountMembership >---- (1) Account
         has_many :through           has_many :through

AccountMembership:
- user_id (FK)
- account_id (FK)
- role (enum: viewer, member, admin, owner)
- status (enum: pending, accepted, declined, revoked)
- invitation_token (string, nullable)
- invitation_sent_at (datetime)
- invitation_accepted_at (datetime)
- invited_by_id (FK to User)
- deleted_at (datetime, soft delete)
```

### Existing Code Locations

| Concern | File Location |
|---------|---------------|
| Membership model | `app/models/account_membership.rb` |
| Role enum | `app/models/concerns/account_membership/validations.rb` |
| Status enum | `app/models/concerns/account_membership/scopes.rb` |
| Permission checks | `app/models/concerns/user/account_access.rb` |
| Current account | `app/controllers/application_controller.rb` |

### New Code Locations (To Create)

| Concern | File Location |
|---------|---------------|
| Team controller | `app/controllers/account/team_controller.rb` |
| Invitation service | `app/services/team/invitation_service.rb` |
| Acceptance service | `app/services/team/acceptance_service.rb` |
| Role change service | `app/services/team/role_change_service.rb` |
| Removal service | `app/services/team/removal_service.rb` |
| Invitation mailer | `app/mailers/team_mailer.rb` |
| Team views | `app/views/account/team/` |
| Authorization concern | `app/controllers/concerns/team_authorization.rb` |

---

## Design Patterns

### Authorization Pattern

Use existing `User::AccountAccess` methods in before_actions:

- `current_user.owner_of?(current_account)` → owner-only actions
- `current_user.admin_of?(current_account)` → admin+ actions
- `current_user.member_of?(current_account)` → any member

Create controller concern for DRY authorization checks across dashboard.

### Service Object Pattern

All team operations use `ApplicationService` base class:
- Return `{ success: true }` or `{ success: false, errors: [...] }`
- Handle edge cases (last owner, self-demotion, etc.)
- Trigger mailers within services

### Invitation Token Pattern

- Generate with `SecureRandom.urlsafe_base64(32)`
- Store hashed with `Digest::SHA256`
- Expire after 7 days
- Single use (clear after acceptance)

### Soft Delete Pattern

- Use `deleted_at` column (already exists)
- Scope queries with `.not_deleted`
- Preserve audit trail
- Allow re-invitation after removal

---

## Account Switching

### Session Management

- `session[:current_account_id]` tracks active account
- On login, default to most recently accessed account
- Store `last_accessed_at` on AccountMembership

### UI Components

- Account switcher dropdown in header
- Show account name + role badge
- Quick switch without re-authentication
- "Create New Account" option for users who want their own

### URL Structure Options

**Option A: Session-based (Recommended)**
- `/dashboard` → uses session's current_account
- Simpler URLs, cleaner bookmarks
- Account switch updates session

**Option B: Account-scoped URLs**
- `/accounts/:account_id/dashboard`
- Explicit, shareable URLs
- More complex routing

---

## Implementation Checklist

### Phase 1: Core Team Page

- [x] Create `Account::TeamController` with index action
- [x] Create team index view listing current members
- [x] Show role badges and status indicators
- [x] Add "Team" link to account settings navigation (already exists)
- [x] Gate access to admin+ roles (view accessible to all, management to admin+)

### Phase 2: Invitation Flow

- [x] Add invite form (email input + role select)
- [x] Create `Team::InvitationService`
- [x] Handle new user vs existing user paths
- [x] Create `TeamMailer` with invitation email
- [ ] Create invitation acceptance page
- [ ] Create `Team::AcceptanceService`
- [x] Add invitation token to AccountMembership migration
- [x] Add invited_by_id to track who sent invite

### Phase 3: Member Management

- [ ] Create `Team::RoleChangeService`
- [ ] Add role change dropdown (admin+ only)
- [ ] Prevent owner demotion without transfer
- [ ] Prevent self-demotion to member
- [ ] Create `Team::RemovalService`
- [ ] Add remove button with confirmation
- [ ] Prevent removing last owner
- [ ] Handle soft delete with deleted_at

### Phase 4: Multi-Account Support

- [ ] Add account switcher component to header
- [ ] Track `last_accessed_at` on membership
- [ ] Update login to select default account
- [ ] Add "Create New Account" flow for existing users
- [ ] Handle pending invitations display

### Phase 5: Ownership Transfer

- [ ] Add transfer ownership action (owner only)
- [ ] Require confirmation (type account name)
- [ ] Create `Team::OwnershipTransferService`
- [ ] Demote previous owner to admin
- [ ] Send notification emails to both parties

### Phase 6: Authorization Hardening

- [ ] Audit all dashboard controllers for role checks
- [ ] Add before_action guards to admin-only actions
- [ ] Restrict attribution model CRUD to admin+
- [ ] Restrict billing pages to admin+
- [ ] Restrict API key management to admin+
- [ ] Add authorization tests for each controller

---

## Edge Cases

### Owner Protection
- Cannot remove the owner
- Cannot demote owner without transferring ownership first
- Account must always have exactly one owner

### Self-Actions
- Users cannot remove themselves (use "Leave Account")
- Users cannot demote themselves below current role
- Owner cannot leave without transferring ownership

### Invitation Edge Cases
- Re-inviting a declined user: Create new invitation
- Re-inviting a removed user: Update existing membership
- Inviting owner's email to own account: Reject with error
- Invitation expiry: 7 days, then requires re-send

### Multi-Account Edge Cases
- User deletes their last owned account: Becomes orphan, prompt to create new
- User accepts invite while logged into different account: Switch context
- Concurrent invitations to same email: Last one wins (idempotent)

---

## Security Considerations

- Rate limit invitation sends (10/hour per account)
- Validate email format before sending
- Hash invitation tokens in database
- Log all role changes for audit trail
- Notify users via email on role changes
- Notify users via email when removed
- Prevent enumeration of existing users via invite response

---

## Database Changes

### New Columns on AccountMembership

| Column | Type | Notes |
|--------|------|-------|
| `invitation_token_digest` | string | Hashed token |
| `invitation_sent_at` | datetime | For expiry calc |
| `invitation_accepted_at` | datetime | Audit trail |
| `invited_by_id` | bigint FK | References users |
| `last_accessed_at` | datetime | For account switching default |

### Indexes

- `account_memberships(invitation_token_digest)` - token lookup
- `account_memberships(user_id, status)` - user's active accounts
- `account_memberships(account_id, status, deleted_at)` - team list

---

## UI/UX Notes

### Team List View
- Table: Name, Email, Role, Status, Joined Date, Actions
- Pending invitations shown with "Pending" badge
- Resend invite button for pending
- Owner has crown icon, no action buttons

### Invite Modal
- Email input with validation
- Role dropdown (Member default, Admin option)
- "Send Invitation" button
- Success toast with email sent confirmation

### Account Switcher
- Dropdown in header next to user menu
- Current account highlighted
- Role shown as badge (Owner/Admin/Member)
- "Create New Account" at bottom

---

## Testing Strategy

### Unit Tests
- `Team::InvitationService` - new user, existing user, validation
- `Team::AcceptanceService` - valid token, expired, already used
- `Team::RoleChangeService` - permission checks, edge cases
- `Team::RemovalService` - soft delete, owner protection
- `User::AccountAccess` - all permission methods

### Integration Tests
- Full invitation flow (new user)
- Full invitation flow (existing user)
- Role change flow
- Member removal flow
- Account switching flow
- Ownership transfer flow

### Authorization Tests
- Each controller action tested with owner, admin, member
- Verify 403 for unauthorized access
- Verify redirect for unauthenticated access
