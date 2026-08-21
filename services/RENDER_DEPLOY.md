# Civic Commons — Render Deployment Guide (Free, No Credit Card)

## Prerequisites
- GitHub account (already have — repo is at github.com:kankan223/pari)
- Render account (free signup at https://render.com — no credit card required)

---

## Step 1: Create Render Account

1. Go to **https://render.com**
2. Click **"Get Started for Free"**
3. Sign up with **GitHub** (recommended — auto-connects your repos)
4. Verify your email

---

## Step 2: Deploy Identity Service

1. In Render Dashboard, click **"New +"** → **"Web Service"**
2. Connect your GitHub repo: `kankan223/pari`
3. Fill in:
   - **Name:** `civic-commons-identity`
   - **Runtime:** `Docker`
   - **Dockerfile Path:** `services/Dockerfile.identity`
   - **Plan:** `Free`
   - **Health Check Path:** `/health`
4. Under **Environment Variables**, add:
   ```
   APP_ENV = staging
   SERVICE_NAME = identity
   HTTP_PORT = 8080
   OTP_PROVIDER = noop
   APP_REQUIRE_POSTGRES = false
   ```
5. **Generate JWT keys first** (see Step 2b below)
6. Click **"Create Web Service"**

### Step 2b: Generate & Set JWT Keys

Before creating the service, generate keys locally:

```bash
# Generate RSA key pair
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out jwt_private.pem
openssl rsa -pubout -in jwt_private.pem -out jwt_public.pem

# Generate Argon2 salt
ARGON2_SALT=$(openssl rand -hex 32)
echo $ARGON2_SALT
```

Then in Render Dashboard → identity service → Environment:
- Add `IDENTITY_DEV_SALT_HEX` = (the hex salt)
- Add `IDENTITY_DEV_JWT_KEY` = (contents of jwt_private.pem)
- Add `IDENTITY_DEV_JWT_PUB_KEY` = (contents of jwt_public.pem)

---

## Step 3: Deploy Relay Service

1. Click **"New +"** → **"Web Service"**
2. Connect the same GitHub repo
3. Fill in:
   - **Name:** `civic-commons-relay`
   - **Runtime:** `Docker`
   - **Dockerfile Path:** `services/Dockerfile.relay`
   - **Plan:** `Free`
   - **Health Check Path:** `/health`
4. Under **Environment Variables**, add:
   ```
   APP_ENV = staging
   SERVICE_NAME = relay
   HTTP_PORT = 8081
   APP_REQUIRE_POSTGRES = false
   IDENTITY_DEV_JWT_PUB_KEY = (contents of jwt_public.pem)
   ```
5. Click **"Create Web Service"**

---

## Step 4: Verify

After deployment (~2-3 minutes):

1. Go to each service's page in Render Dashboard
2. Check the **Logs** tab — look for "service listening" messages
3. Click the service URL to verify it responds
4. The URLs will be:
   - Identity: `https://civic-commons-identity.onrender.com`
   - Relay: `https://civic-commons-relay.onrender.com`

---

## Important Notes

### Free Tier Limitations
- **Spin down after 15 minutes** of no traffic (cold start ~30s on next request)
- **750 hours/month** total (enough for both services)
- **No custom domains** on free tier (use the `.onrender.com` URLs)
- **No persistent storage** — but our services use external Redis/Postgres

### Upgrading Later
When you get traffic, upgrade to:
- **Starter plan ($7/mo each)** — no spin-down, always-on
- **Add custom domains** — `api.civiccommons.org` and `ws.civiccommons.org`

### Adding Redis Later
Render doesn't have free Redis. Use **Upstash** (free tier):
1. Sign up at https://upstash.com (free, no credit card)
2. Create a Redis database
3. Copy the connection URL
4. Add `REDIS_ADDR = <your-upstash-url>` to both services in Render

### Adding PostgreSQL Later
Render's free PostgreSQL expires after 90 days. Alternatives:
- **Supabase** (free, 500MB) — https://supabase.com
- **Neon** (free, 512MB) — https://neon.tech
- **Railway** (free trial) — https://railway.app

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Service won't start | Check logs — usually missing env vars |
| "no salt source configured" | Set IDENTITY_DEV_SALT_HEX |
| "no jwt public key source" | Set IDENTITY_DEV_JWT_PUB_KEY |
| Cold start takes 30s | Normal for free tier — upgrade to Starter for always-on |
| Build fails | Ensure Dockerfile paths are correct in Render settings |
