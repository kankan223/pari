# Civic Commons — Backend Deployment Guide

## Quick Start (5 minutes)

### 1. Install Fly CLI

```bash
curl -L https://fly.io/install.sh | sh
export FLYCTL_INSTALL="$HOME/.fly"
export PATH="$FLYCTL_INSTALL/bin:$PATH"
```

### 2. Sign Up & Login

```bash
flyctl auth signup    # Creates a free Fly.io account
flyctl auth login     # Authenticates your CLI
```

### 3. Deploy Identity Service

```bash
cd services

# Generate JWT keys (save these — you'll need them for the relay too)
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out jwt_private.pem
openssl rsa -pubout -in jwt_private.pem -out jwt_public.pem
ARGON2_SALT=$(openssl rand -hex 32)

# Set env vars (replace with your actual key contents)
export JWT_PRIV_KEY=$(cat jwt_private.pem)
export JWT_PUB_KEY=$(cat jwt_public.pem)

# Create and deploy
flyctl launch --config fly.identity.toml --name civic-commons-identity

# Set secrets
flyctl secrets set \
  IDENTITY_DEV_SALT_HEX="$ARGON2_SALT" \
  IDENTITY_DEV_JWT_KEY="$JWT_PRIV_KEY" \
  IDENTITY_DEV_JWT_PUB_KEY="$JWT_PUB_KEY"

# Deploy
flyctl deploy --config fly.identity.toml --app civic-commons-identity
```

### 4. Deploy Relay Service

```bash
# The relay needs the PUBLIC key from the identity service
flyctl launch --config fly.relay.toml --name civic-commons-relay

# Set the JWT public key (same as identity service)
flyctl secrets set \
  IDENTITY_DEV_JWT_PUB_KEY="$JWT_PUB_KEY" \
  --app civic-commons-relay

# Deploy
flyctl deploy --config fly.relay.toml --app civic-commons-relay
```

### 5. Verify

```bash
# Check identity service
flyctl status --app civic-commons-identity
flyctl logs --app civic-commons-identity

# Check relay service
flyctl status --app civic-commons-relay
flyctl logs --app civic-commons-relay
```

## Free Tier Limits

- **3 shared-cpu-1x VMs** (256MB each) — enough for both services
- **3GB persistent storage** — for PostgreSQL (if needed later)
- **160GB bandwidth/month** — sufficient for WebSocket traffic
- **Auto-stop** — VMs stop when idle, wake on request (cold start ~5s)

## Environment Variables

### Identity Service
| Variable | Required | Description |
|----------|----------|-------------|
| `APP_ENV` | Yes | `staging` (allows dev fallbacks) |
| `IDENTITY_DEV_SALT_HEX` | Yes | 64-char hex Argon2 salt |
| `IDENTITY_DEV_JWT_KEY` | Yes | RSA private key PEM |
| `IDENTITY_DEV_JWT_PUB_KEY` | No | RSA public key PEM (derived from private) |
| `OTP_PROVIDER` | No | `noop` (default) or `msg91` |

### Relay Service
| Variable | Required | Description |
|----------|----------|-------------|
| `APP_ENV` | Yes | `staging` (allows dev fallbacks) |
| `IDENTITY_DEV_JWT_PUB_KEY` | Yes | RSA public key PEM for token verification |
| `APP_REQUIRE_POSTGRES` | No | `false` (default: skips PG) |

## Adding a Custom Domain

```bash
# Add a custom domain to the identity service
flyctl certs create api.yourdomain.com --app civic-commons-identity

# Add a custom domain to the relay service
flyctl certs create ws.yourdomain.com --app civic-commons-relay
```

## Scaling Up

When you need more resources:

```bash
# Scale to a dedicated VM
flyctl scale vm performance-cx --app civic-commons-identity

# Add a second instance
flyctl scale count 2 --app civic-commons-identity

# Add persistent storage for PostgreSQL
flyctl volumes create pg_data --size 3 --app civic-commons-identity
```

## Production Checklist

- [ ] Set `APP_ENV=production` (requires Vault for secrets)
- [ ] Set up HashiCorp Vault for JWT keys and Argon2 salt
- [ ] Configure PostgreSQL with proper `POSTGRES_DSN`
- [ ] Set `PG_ENC_KEY` for pgcrypto at-rest encryption
- [ ] Enable MSG91 OTP provider for real SMS
- [ ] Set up NATS JetStream for event bus
- [ ] Configure CORS for production domains
- [ ] Set up monitoring and alerting
