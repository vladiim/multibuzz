# Shopify App Deployment Spec

**Status**: Ready for Implementation
**Created**: 2025-12-22
**Target**: New DigitalOcean Droplet via Kamal

---

## Overview

Deploy the mbuzz Shopify app (`/Users/vlad/code/m/mbuzz-shopify`) to a dedicated DigitalOcean droplet using Kamal.

---

## Infrastructure

| Component | Value |
|-----------|-------|
| Server | New DO droplet (to be created) |
| Domain | `shopify.mbuzz.co` |
| Registry | ghcr.io/vladiim/mbuzz-shopify |
| Secrets | LastPass |
| Database | SQLite (persisted volume) |
| Region | SFO3 or NYC1 (same as main app) |
| Size | Basic ($6/mo, 1GB RAM, 1 vCPU) |

---

## Setup Steps

### 1. Create DigitalOcean Droplet

1. Go to DigitalOcean → Create → Droplets
2. **Image**: Ubuntu 24.04 LTS
3. **Size**: Basic, $6/mo (1 GB / 1 CPU)
4. **Region**: Same as main app
5. **SSH Keys**: Select existing key
6. **Hostname**: `mbuzz-shopify`
7. Create Droplet
8. Note the IP address: `___.___.___.__`

### 2. DNS Configuration

Add A record in Cloudflare:

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| A | shopify | (droplet IP) | Proxied |

Set SSL/TLS mode to "Full" for subdomain.

### 3. Add Secrets to LastPass

Under `mbuzz` folder:

| Secret | Source |
|--------|--------|
| MBUZZ_SHOPIFY_API_KEY | Partners Dashboard → Apps → mbuzz Attribution |
| MBUZZ_SHOPIFY_API_SECRET | Same location |

---

## Files to Create in mbuzz-shopify

### 1. Dockerfile

```dockerfile
# syntax=docker/dockerfile:1

FROM node:20-slim AS builder
WORKDIR /app

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y openssl && \
    rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npx prisma generate && npm run build

FROM node:20-slim
WORKDIR /app

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y openssl && \
    rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY prisma ./prisma
RUN npx prisma generate

COPY --from=builder /app/build ./build

RUN mkdir -p /data && chown -R node:node /data /app
USER node

ENV NODE_ENV=production
ENV DATABASE_URL="file:/data/shopify.sqlite"
ENV PORT=3000

EXPOSE 3000

CMD ["sh", "-c", "npx prisma migrate deploy && npx remix-serve ./build/server/index.js"]
```

### 2. config/deploy.yml

```yaml
service: mbuzz-shopify

image: vladiim/mbuzz-shopify

servers:
  web:
    - DROPLET_IP_HERE

proxy:
  ssl: true
  hosts:
    - shopify.mbuzz.co

registry:
  server: ghcr.io
  username: vladiim
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  secret:
    - SHOPIFY_API_KEY
    - SHOPIFY_API_SECRET
  clear:
    NODE_ENV: production
    PORT: 3000
    SHOPIFY_APP_URL: https://shopify.mbuzz.co
    SCOPES: "read_orders,read_customers,write_script_tags,read_customer_events"

volumes:
  - "mbuzz_shopify_data:/data"

builder:
  arch: amd64

aliases:
  logs: app logs -f
  shell: app exec --interactive --reuse "sh"
```

### 3. .kamal/secrets

```bash
SECRETS=$(kamal secrets fetch --adapter lastpass --account vlad@mehakovic.com --from mbuzz MBUZZ_KAMAL_REGISTRY_PASSWORD MBUZZ_SHOPIFY_API_KEY MBUZZ_SHOPIFY_API_SECRET)

KAMAL_REGISTRY_PASSWORD=$(kamal secrets extract mbuzz/MBUZZ_KAMAL_REGISTRY_PASSWORD "\"${SECRETS}\"")
SHOPIFY_API_KEY=$(kamal secrets extract mbuzz/MBUZZ_SHOPIFY_API_KEY "\"${SECRETS}\"")
SHOPIFY_API_SECRET=$(kamal secrets extract mbuzz/MBUZZ_SHOPIFY_API_SECRET "\"${SECRETS}\"")
```

---

## Update Shopify Configuration

### shopify.app.toml

```toml
name = "mbuzz Attribution"
client_id = "b13c6d944b53ac1e322ccf4b5d476660"
application_url = "https://shopify.mbuzz.co"
embedded = true

[access_scopes]
scopes = "read_orders,read_customers,write_script_tags,read_customer_events"

[auth]
redirect_urls = ["https://shopify.mbuzz.co/auth/callback"]

[webhooks]
api_version = "2024-10"

[pos]
embedded = false

[build]
automatically_update_urls_on_dev = true
```

### Shopify Partners Dashboard

1. Apps → mbuzz Attribution → Configuration
2. Set App URL: `https://shopify.mbuzz.co`
3. Set Redirect URL: `https://shopify.mbuzz.co/auth/callback`

---

## Deployment

```bash
cd /Users/vlad/code/m/mbuzz-shopify

# Initial setup (first deploy)
bin/kamal setup

# Subsequent deploys
bin/kamal deploy
```

---

## App Store Submission

After deployment verified:

```bash
shopify app versions create --release
```

### Update SDK Registry

After approval, in multibuzz repo:

```yaml
# config/sdk_registry.yml
shopify:
  status: live
```

---

## Operations

| Command | Description |
|---------|-------------|
| `bin/kamal deploy` | Deploy new version |
| `bin/kamal logs` | View logs |
| `bin/kamal rollback` | Rollback to previous |
| `bin/kamal shell` | Shell access |
