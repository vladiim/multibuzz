# User Account Memberships

**Status**: Complete
**Created**: 2025-11-27
**Completed**: 2025-11-27

---

## Summary

Replaced `users.account_id` FK with `account_memberships` join table to enable multi-account users and per-account roles.

---

## Database

### New Table: `account_memberships`

| Column | Type | Notes |
|--------|------|-------|
| `user_id` | bigint | FK, not null |
| `account_id` | bigint | FK, not null |
| `role` | integer | enum: viewer(0), member(1), admin(2), owner(3) |
| `status` | integer | enum: pending(0), accepted(1), declined(2), revoked(3) |
| `invited_at` | datetime | |
| `accepted_at` | datetime | |
| `invited_by_email` | string | audit trail |
| `deleted_at` | datetime | soft delete |

**Indexes**: `[user_id, account_id]` unique (where deleted_at IS NULL), `[account_id, role]`, `[account_id, status]`

### Migration Strategy

1. Create `account_memberships` table
2. Migrate existing `users.account_id` → memberships (admin→owner, member→member)
3. Remove `users.account_id` and `users.role` columns

---

## Models

### AccountMembership (New)

**Location**: `app/models/account_membership.rb`

```
belongs_to :user
belongs_to :account
enum :role, { viewer: 0, member: 1, admin: 2, owner: 3 }
enum :status, { pending: 0, accepted: 1, declined: 2, revoked: 3 }
scope :active, -> { accepted }
```

**Concerns**: `Validations`, `Relationships`, `Scopes`

**Validation**: User can only have one membership per account. Account must always have one owner.

### User (Updated)

**Changes to** `app/models/concerns/user/relationships.rb`:
- Remove: `belongs_to :account`
- Add: `has_many :account_memberships`, `has_many :accounts, through: :account_memberships`

**New concern** `app/models/concerns/user/account_access.rb`:
- `#member_of?(account)` - has accepted membership?
- `#admin_of?(account)` - admin or owner?
- `#owner_of?(account)` - owner?
- `#role_for(account)` - returns role string
- `#primary_account` - first owned or first joined

### Account (Updated)

**Changes to** `app/models/concerns/account/relationships.rb`:
- Remove: `has_many :users`
- Add: `has_many :account_memberships`, `has_many :users, through: :account_memberships`
- Add: `has_many :active_members` (scoped through)

---

## Services

### AccountMemberships::InvitationService

**Location**: `app/services/account_memberships/invitation_service.rb`

**Input**: `account`, `inviter` (user), `email`, `role`

**Logic**:
- Verify inviter is admin/owner
- Verify role ≤ inviter's role (can't grant higher)
- Check user not already active member
- Create pending membership
- (Future: send email)

### AccountMemberships::AcceptanceService

**Location**: `app/services/account_memberships/acceptance_service.rb`

**Input**: `membership`, `user`

**Logic**:
- Verify user owns the invitation
- Verify membership is pending
- Set status=accepted, accepted_at=now

---

## Tests

### Fixtures

**Location**: `test/fixtures/account_memberships.yml`

```yaml
owner_one:
  user: one
  account: one
  role: 3  # owner
  status: 1  # accepted

member_two:
  user: two
  account: one
  role: 1  # member
  status: 1  # accepted
```

### Test Files

- `test/models/account_membership_test.rb` - uniqueness, owner protection
- `test/models/concerns/user/account_access_test.rb` - role checks, active_accounts
- `test/services/account_memberships/invitation_service_test.rb`
- `test/services/account_memberships/acceptance_service_test.rb`

---

## Implementation Order

1. Create migration: `account_memberships` table
2. Create model: `AccountMembership` with concerns
3. Create migration: migrate existing data
4. Update `User` model (add new relationships, keep old)
5. Update `Account` model (add new relationships, keep old)
6. Add `User::AccountAccess` concern
7. Write tests
8. Create migration: remove old columns
9. Update any controllers using old associations

---

## Verification Queries

```ruby
# After migration - verify integrity
User.left_joins(:account_memberships).where(account_memberships: { id: nil }).count
# => 0 (all users have memberships)

Account.left_joins(:account_memberships).where(account_memberships: { id: nil }).count
# => 0 (all accounts have memberships)

Account.all.select { |a| a.account_memberships.owner.accepted.none? }
# => [] (all accounts have owners)
```

---

## Notes

- Keep `dependent: :destroy` on account→memberships (not on user→memberships to avoid orphaning)
- Current prod has 1 user, 1 account - simple migration
- Role hierarchy: owner > admin > member > viewer
- Pending invitations don't grant access until accepted
