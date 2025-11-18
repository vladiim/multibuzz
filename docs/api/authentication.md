# Authentication

All Multibuzz API requests require authentication using API keys passed via Bearer tokens.

## API Keys

### Key Format

API keys follow this format:

```
sk_{environment}_{random32}
```

Where:
- `sk` - Prefix indicating "secret key"
- `{environment}` - Either `test` or `live`
- `{random32}` - 32 cryptographically random characters

**Examples:**
```
sk_test_********************************
sk_live_********************************
```

### Environments

#### Test Environment
- **Purpose**: Development and testing
- **Rate Limit**: 1,000 requests/hour
- **Data**: Isolated test data, can be reset
- **Key Prefix**: `sk_test_`

#### Live Environment
- **Purpose**: Production traffic
- **Rate Limit**: 10,000 requests/hour
- **Data**: Real production data
- **Key Prefix**: `sk_live_`

### Creating API Keys

1. Log in to your [Multibuzz Dashboard](https://multibuzz.io/dashboard)
2. Navigate to **Settings → API Keys**
3. Click **Create API Key**
4. Select environment (Test or Live)
5. Optional: Add a description (e.g., "Production Server", "Staging Environment")
6. Click **Create**
7. **Copy your key immediately** - it will only be shown once

**⚠️ Security Warning**: API keys are shown in full only once during creation. Store them securely in environment variables or a secrets manager. Never commit them to version control.

### Using API Keys

Include your API key in the `Authorization` header of every request:

```http
Authorization: Bearer sk_test_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6
```

**cURL Example:**
```bash
curl -X POST https://multibuzz.io/api/v1/events \
  -H "Authorization: Bearer sk_test_YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"events": [...]}'
```

**Ruby Example:**
```ruby
require 'net/http'

uri = URI('https://multibuzz.io/api/v1/events')
request = Net::HTTP::Post.new(uri)
request['Authorization'] = "Bearer #{ENV['MULTIBUZZ_API_KEY']}"
request['Content-Type'] = 'application/json'
```

**JavaScript Example:**
```javascript
fetch('https://multibuzz.io/api/v1/events', {
  method: 'POST',
  headers: {
    'Authorization': `Bearer ${process.env.MULTIBUZZ_API_KEY}`,
    'Content-Type': 'application/json'
  }
})
```

### Validating API Keys

Test your API key before making tracking requests:

```bash
curl -X GET https://multibuzz.io/api/v1/validate \
  -H "Authorization: Bearer sk_test_YOUR_API_KEY"
```

**Success Response (200 OK):**
```json
{
  "valid": true,
  "account": {
    "id": "acc_abc123",
    "name": "Acme Inc",
    "status": "active"
  },
  "environment": "test"
}
```

**Error Response (401 Unauthorized):**
```json
{
  "error": "Unauthorized",
  "details": "Invalid or expired API key",
  "code": "invalid_api_key"
}
```

### Managing API Keys

#### Listing Keys

View all your API keys in the [Dashboard → API Keys](https://multibuzz.io/dashboard/api-keys) page. You'll see:
- Key prefix (first 12 characters, e.g., `sk_test_a1b2...`)
- Description
- Environment (Test/Live)
- Created date
- Last used date
- Status (Active/Revoked)

#### Revoking Keys

Revoke a compromised or unused key immediately:

1. Navigate to **Settings → API Keys**
2. Find the key to revoke
3. Click **Revoke**
4. Confirm revocation

**Note**: Revoked keys cannot be restored. Create a new key if needed.

#### Key Rotation

Best practice: Rotate keys periodically (every 90 days recommended).

**Rotation Process:**
1. Create a new API key
2. Update your application to use the new key
3. Deploy the change
4. Verify the new key is working
5. Revoke the old key

## Authentication Errors

### Missing Authorization Header

**Request:**
```bash
curl -X POST https://multibuzz.io/api/v1/events \
  -H "Content-Type: application/json" \
  -d '{"events": [...]}'
```

**Response (401 Unauthorized):**
```json
{
  "error": "Unauthorized",
  "details": "Missing Authorization header",
  "code": "missing_api_key"
}
```

### Invalid API Key

**Response (401 Unauthorized):**
```json
{
  "error": "Unauthorized",
  "details": "Invalid or expired API key",
  "code": "invalid_api_key"
}
```

### Revoked API Key

**Response (401 Unauthorized):**
```json
{
  "error": "Unauthorized",
  "details": "API key has been revoked",
  "code": "revoked_api_key"
}
```

### Wrong Environment

Using a test key when live is required (or vice versa):

**Response (401 Unauthorized):**
```json
{
  "error": "Unauthorized",
  "details": "Test keys cannot be used in production",
  "code": "invalid_environment"
}
```

## Security Best Practices

### ✅ Do

- **Store keys in environment variables**
  ```bash
  export MULTIBUZZ_API_KEY=sk_test_a1b2c3d4...
  ```

- **Use secrets management** (AWS Secrets Manager, HashiCorp Vault, etc.)

- **Separate test and live keys** - Use test keys in development, live keys in production

- **Rotate keys regularly** - Every 90 days recommended

- **Revoke immediately** if compromised

- **Make API calls server-side** - Never expose keys in client-side code

- **Use HTTPS** - All API calls must use HTTPS (enforced)

- **Limit key permissions** - Create separate keys per service/environment

### ❌ Don't

- **Never commit keys to version control**
  ```bash
  # .gitignore
  .env
  .env.local
  secrets.yml
  ```

- **Never log keys** - Redact from logs and error messages

- **Never share keys** - Each team member/service should have their own

- **Never use live keys in development** - Always use test keys

- **Never expose in client-side code** - Keep keys on your backend

- **Never hardcode keys** - Use environment variables or secret managers

## Rate Limiting

API keys are subject to rate limits based on environment:

| Environment | Limit | Window |
|-------------|-------|--------|
| Test | 1,000 requests | per hour |
| Live | 10,000 requests | per hour |

**Rate limit headers** included in every response:

```http
X-RateLimit-Limit: 10000
X-RateLimit-Remaining: 9847
X-RateLimit-Reset: 1699358400
```

**When limit exceeded (429 Too Many Requests):**
```json
{
  "error": "Too Many Requests",
  "details": "Rate limit exceeded. Limit: 10000 requests/hour",
  "code": "rate_limit_exceeded"
}
```

See [Rate Limits](rate_limits.md) for details.

## Multi-Tenancy

Each API key is scoped to a single **Account** (tenant). Data is strictly isolated:

- Events tracked with one API key are only visible to that account
- Cross-account access is prevented at the database level
- Dashboard users only see their account's data
- API responses never leak data from other accounts

## Implementation Details

### Key Storage

API keys are **hashed** before storage using SHA256:

```ruby
# What we store in the database
{
  key_prefix: "sk_test_a1b2",      # First 12 chars for display
  key_digest: "sha256_hash...",     # SHA256 hash of full key
  environment: "test",
  account_id: 123
}
```

**You cannot retrieve the original key** - it's only shown once during creation.

### Key Validation Process

1. Extract Bearer token from `Authorization` header
2. Hash the provided key with SHA256
3. Look up key by digest in database
4. Check if key is active (not revoked)
5. Load associated account
6. Verify account is active (not suspended/cancelled)
7. Return account for request context

### Performance

- API key lookup is optimized with database indexes
- Keys are cached for 5 minutes after validation
- Average validation time: <5ms

## Troubleshooting

### "Invalid API key" Error

**Possible causes:**
1. Typo in the key
2. Key was revoked
3. Key hasn't synced yet (wait 30 seconds after creation)
4. Using wrong environment key

**Solutions:**
- Double-check key matches exactly (copy-paste)
- Verify key is Active in dashboard
- Create a new key if needed

### "Missing Authorization header" Error

**Possible causes:**
1. Header not included in request
2. Header name is incorrect
3. Malformed header value

**Solutions:**
```bash
# ❌ Wrong
curl -X POST https://multibuzz.io/api/v1/events

# ❌ Wrong header name
curl -X POST https://multibuzz.io/api/v1/events \
  -H "X-API-Key: sk_test_..."

# ❌ Missing "Bearer" prefix
curl -X POST https://multibuzz.io/api/v1/events \
  -H "Authorization: sk_test_..."

# ✅ Correct
curl -X POST https://multibuzz.io/api/v1/events \
  -H "Authorization: Bearer sk_test_..."
```

### Rate Limit Issues

**Solutions:**
- Implement exponential backoff
- Batch events (up to 100 per request)
- Upgrade to higher tier (contact support)
- Use test environment for development

## Next Steps

- 📖 [Getting Started Guide](getting_started.md) - Make your first API call
- 📊 [Event Tracking](events.md) - Track page views and custom events
- 🚦 [Rate Limits](rate_limits.md) - Understanding rate limits
- 🔍 [API Reference](openapi.yml) - Complete API documentation
