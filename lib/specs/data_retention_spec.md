# Data Retention Specification

**Status**: Planned
**Priority**: P1 (Required for Privacy Policy compliance)
**Last Updated**: 2025-11-29

---

## Overview

Defines data retention policies for mbuzz, referenced in the Privacy Policy.

---

## Retention Periods

### Customer Account Data

| Data Type | Retention | Notes |
|-----------|-----------|-------|
| Account info (email, name) | 90 days post-deletion | Allows reactivation window |
| Billing records | 7 years | Legal/tax requirement (store separately) |
| API keys | Immediate | Security-sensitive |
| Login sessions | Immediate | Security-sensitive |

### End-User Data (Customer's tracking data)

| Data Type | Retention | Notes |
|-----------|-----------|-------|
| Events, Sessions, Visitors, Conversions, Touchpoints, Identities | Immediate | Customer owns this data; delete on account deletion or customer request |

### Operational Data

| Data Type | Retention |
|-----------|-----------|
| Server logs | 30 days |
| Error logs | 90 days |
| Support emails | 2 years post-resolution |

---

## Account Deletion Flow

### Trigger
Customer requests deletion via dashboard settings or email to privacy@mbuzz.co

### Sequence

1. **Immediate**: Delete all end-user data (events, sessions, visitors, etc.)
2. **Immediate**: Delete API keys and login sessions
3. **Mark account**: Set status to `pending_deletion`, record `deletion_scheduled_at`
4. **90 days later**: Background job permanently deletes account and user records
5. **Retained**: Billing records moved to separate storage (7-year retention)

### Reactivation Window

During 90-day window:
- Customer can log in and cancel deletion
- Account data preserved but inactive
- End-user data already gone (unrecoverable)
- Show clear warning: "Your tracking data has been permanently deleted"

---

## Key Objects

| Object | Purpose |
|--------|---------|
| `Account::DeletionService` | Orchestrates deletion flow |
| `Account::PermanentDeletionJob` | Scheduled job for final deletion |
| `Account#pending_deletion?` | Status check |
| `Account#deletion_scheduled_at` | Timestamp for scheduled deletion |
| `BillingRecord` | Separate model for long-term billing retention |
| `DeletionAuditLog` | Compliance trail of all deletion requests |

---

## Customer-Initiated Data Deletion (GDPR Support)

Customers may need to delete specific end-user data without deleting their account (to comply with their own users' GDPR requests).

| Endpoint | Purpose |
|----------|---------|
| `DELETE /api/v1/data/visitors/:visitor_id` | Delete specific visitor and their data |
| `DELETE /api/v1/data/all` | Reset account (delete all tracking data) |

---

## Database Changes

| Table | Change |
|-------|--------|
| `accounts` | Add `deletion_scheduled_at:datetime` |
| `accounts` | Add `pending_deletion` to status enum |
| `billing_records` | New table with denormalized account email, invoice data |
| `deletion_audit_logs` | New table for compliance audit trail |

---

## Design Patterns

- **Soft delete for accounts**: Use `deletion_scheduled_at` rather than immediate hard delete
- **Hard delete for end-user data**: Privacy-first, no soft delete
- **Separate billing storage**: Decouple from account lifecycle for tax compliance
- **Audit everything**: Log who requested what, when, and what was deleted
- **Background jobs**: Use Solid Queue for scheduled permanent deletion

---

## Privacy Policy Reference

The Privacy Policy at `/privacy` references these retention periods. Changes here must sync with Privacy Policy.
