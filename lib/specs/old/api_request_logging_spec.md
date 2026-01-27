# API Request Logging Specification

## Overview

Database-backed request logging system for API failures, enabling debugging, monitoring, and proactive alerting.

**Status**: Phase 1 & 2 Complete
**Last Updated**: 2026-01-15

---

## Problem Statement

API failures are invisible. When the Jan 2026 visitor creation incident caused 80% conversion drop over 4 days, discovery required manual database queries. No proactive alerting existed.

**Current gaps**:
- No failure persistence or audit trail
- No SDK version tracking per request
- No rejection rate monitoring
- No time-series analysis of failure patterns
- No alerting for sudden spikes

---

## Domain Model

### Naming: `ApiRequestLog`

Extensible naming rationale:
- `ApiRequestLog` (not `ApiErrorLog`) - can extend to success logging if needed
- `ApiRequestLog` (not `RequestLog`) - scoped to API, leaves room for webhook logs, job logs
- Singular table: `api_request_logs`

### Related Future Models (extensibility)

| Model | Purpose | When |
|-------|---------|------|
| `ApiRequestLog` | API failure/success logging | Now |
| `WebhookDeliveryLog` | Outbound webhook attempts | Future |
| `JobExecutionLog` | Background job failures | Future |
| `AuditLog` | User action audit trail | Future |

All could share a common `Loggable` concern for timestamps, retention, cleanup.

---

## Best Practices Review

### Industry Standards Comparison

| Practice | Industry Standard | Our Current State |
|----------|-------------------|-------------------|
| Structured logging | JSON with consistent fields | ❌ None |
| Request correlation IDs | UUID per request | ❌ Not implemented |
| Error classification | Enumerated types | ❌ Ad-hoc strings |
| Account context | Link failures to accounts | ❌ Lost after response |
| SDK version tracking | Parse from User-Agent | ⚠️ Available but not stored |
| Retention policies | 90 days errors, 30 days access | ❌ No retention |
| Alerting | Threshold-based, anomaly detection | ❌ None |

### What to Log

**Always**:
- Timestamp, request ID, account ID
- Endpoint, HTTP method, status code
- Error type (enumerated), error message
- SDK name and version

**Conditionally**:
- Sanitized request params (for debugging)
- Anonymized IP (first 3 octets)
- Response time

**Never**:
- Passwords, API keys, tokens
- Full PII

---

## Technical Architecture

### Design Patterns

| Pattern | Application |
|---------|-------------|
| **Service Object** | `ApiRequestLogs::RecordService` - single responsibility for log creation |
| **Enum for Types** | `error_type` as Rails enum - type safety, scopes, predicates |
| **Concern Extraction** | `Loggable` concern for shared retention/cleanup logic |
| **Observer/Callback** | Controller `after_action` or explicit calls at failure points |
| **JSONB for Flexibility** | `error_details` column for variable structured data |

### Data Flow

```
Request → Controller → Service
                ↓ (on failure)
        ApiRequestLogs::RecordService
                ↓
        api_request_logs table
                ↓
        Cleanup Job (90-day retention)
```

### Integration Points

| Location | Failure Type | Integration Method |
|----------|--------------|-------------------|
| `BaseController` | Auth failures (401) | `render_unauthorized` helper |
| `EventsController` | Rejections in batch | Loop through `result[:rejected]` |
| `ConversionsController` | Validation failures | Check `result[:success]` |
| `SessionsController` | Creation failures | Check `result[:success]` |

### Schema Design

```
api_request_logs
├── id (bigint)
├── account_id (nullable FK) ──→ accounts
├── request_id (string, indexed) - UUID correlation
├── endpoint (string) - "events", "conversions", etc.
├── http_method (string)
├── http_status (integer)
├── error_type (integer, enum)
├── error_code (string, nullable)
├── error_message (text)
├── error_details (jsonb) - flexible structured data
├── sdk_name (string)
├── sdk_version (string)
├── ip_address (string, anonymized)
├── user_agent (string)
├── request_params (jsonb, sanitized)
├── response_time_ms (integer)
├── occurred_at (datetime, indexed)
└── timestamps
```

### Error Type Enum

| Category | Types |
|----------|-------|
| **Auth (401)** | `auth_missing_header`, `auth_malformed_header`, `auth_invalid_key`, `auth_revoked_key`, `auth_account_suspended` |
| **Validation (400)** | `validation_missing_param`, `validation_invalid_format`, `validation_invalid_type` |
| **Business (422)** | `visitor_not_found`, `event_not_found`, `conversion_type_missing`, `rate_limit_exceeded`, `billing_blocked` |
| **Server (500)** | `internal_error`, `database_error`, `timeout_error` |

### Indexes Strategy

| Index | Query Pattern |
|-------|---------------|
| `account_id, occurred_at` | Account-specific failure history |
| `error_type, occurred_at` | Error type trends |
| `endpoint, http_status, occurred_at` | Endpoint health |
| `sdk_name, sdk_version, occurred_at` | SDK version analysis |
| `request_id` | Correlation lookup |

---

## Features

### F1: Failure Capture
Automatically log all API failures with full context for debugging.

### F2: Error Classification
Enumerated error types for consistent categorization and querying.

### F3: SDK Version Tracking
Parse and store SDK name/version from User-Agent for version mismatch detection.

### F4: Account Attribution
Link failures to accounts (when authenticated) for customer support.

### F5: Request Correlation
UUID request IDs for tracing failures across systems.

### F6: Data Retention
Automated 90-day cleanup to manage storage growth.

### F7: Query Interface
Scopes and methods for common failure analysis queries.

### F8: Alerting Hooks (Future)
Threshold-based and anomaly detection for proactive monitoring.

---

## Implementation Checklist

### Phase 1: Core Infrastructure
- [x] Create migration for `api_request_logs` table
- [x] Create `ApiRequestLog` model with enum, validations, concerns
- [x] Create `ApiRequestLogs::RecordService`
- [x] Add User-Agent parsing for SDK name/version
- [x] Add IP anonymization helper
- [x] Add request param sanitization
- [x] Write unit tests for model
- [x] Write unit tests for service

### Phase 2: Controller Integration
- [x] Add `log_request_failure` helper to `BaseController`
- [x] Integrate auth failure logging in `BaseController`
- [x] Integrate rejection logging in `EventsController`
- [x] Integrate failure logging in `ConversionsController`
- [x] Integrate failure logging in `SessionsController`
- [ ] Integrate failure logging in `IdentifyController`
- [x] Write integration tests

### Phase 3: Queries & Retention
- [x] Add query scopes to model (by_account, by_error_type, recent, etc.)
- [ ] Create `ApiRequestLogs::CleanupJob`
- [ ] Add to Solid Queue recurring schedule (daily 3am)
- [ ] Write job tests

### Phase 4: Monitoring (Future)
- [ ] Create spike detection query/job
- [ ] Create SDK version anomaly detection
- [ ] Integrate with notification system (email/Slack)

### Phase 5: Dashboard (Future)
- [ ] Admin API health dashboard view
- [ ] Error rate chart (24h, hourly)
- [ ] Top error types breakdown
- [ ] SDK version distribution
- [ ] Per-account failure view for support

---

## Query Patterns

| Query | Purpose |
|-------|---------|
| Failures by type (24h) | Identify most common issues |
| Visitor not found by account | Detect SDK integration issues |
| SDK version distribution | Track SDK adoption |
| Hourly failure trend | Spot spikes/incidents |
| Account recent failures | Customer support debugging |

---

## Alerting Rules (Future)

| Rule | Trigger | Action |
|------|---------|--------|
| Error spike | >50% increase vs previous hour | Slack notification |
| Old SDK version | >100 requests from deprecated SDK | Slack notification |
| Account failure surge | >50 failures for single account in 1h | Slack notification |
| Visitor not found spike | >20% of events rejected | Slack notification |

---

## Success Metrics

After implementation:
1. **Incident detection**: Hours not days
2. **Customer debugging**: "Account X had 50 visitor_not_found errors yesterday"
3. **SDK tracking**: "80% requests from SDK v0.7.1+"
4. **Proactive alerts**: Notification on anomalies

---

## References

- [API Request Logging Best Practices - DreamFactory](https://blog.dreamfactory.com/api-request-logging-best-practices)
- [REST API Error Handling - Treblle](https://treblle.com/blog/rest-api-error-handling)
- [API Error Handling 2025 - APILayer](https://blog.apilayer.com/best-practices-for-rest-api-error-handling-in-2025/)
- [Audit Logging in Rails - AppSignal](https://blog.appsignal.com/2023/04/12/audit-logging-in-ruby-and-rails.html)
- [Database Design for Audit Logging - Vertabelo](https://vertabelo.com/blog/database-design-for-audit-logging/)

---

## Related Documents

- `lib/specs/incidents/2026-01-15-visitor-creation-drop.md` - Motivating incident
- `lib/specs/require_existing_visitor_spec.md` - Visitor validation context
