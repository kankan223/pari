# Civic Commons — Production Deployment Plan

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        CDN / Edge                                │
│  Cloudflare Pages (free) → Vercel (paid) → Cloudflare (scale)   │
├─────────────────────────────────────────────────────────────────┤
│                    Flutter Web App                               │
│  build/web/ → static assets served from edge                    │
├─────────────────────────────────────────────────────────────────┤
│                    Go Backend Services                           │
│  Identity Service (OTP + JWT + blind hash)                      │
│  Messaging Relay (WebSocket + offline queue)                    │
│  API Gateway (Kong OSS 3.x)                                     │
├─────────────────────────────────────────────────────────────────┤
│                    Data Layer                                    │
│  PostgreSQL 16 (SQLCipher on client)                             │
│  Redis (OTP codes, refresh tokens, offline queue)               │
│  HashiCorp Vault (secrets, salt, JWT keys)                      │
├─────────────────────────────────────────────────────────────────┤
│                    Infrastructure                                │
│  Kubernetes (Helm charts) / Docker Compose (dev)                │
│  ArgoCD (GitOps) / GitHub Actions (CI/CD)                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Free Tier Deployment (Current)

### Frontend (Flutter Web)

**Option A: Cloudflare Pages (Recommended — Free)**
- **Free tier:** 500 builds/month, unlimited requests, global CDN
- **Setup:** Connect GitHub repo → auto-deploy on push to `main`
- **Custom domain:** Add `civiccommons.org` in Cloudflare DNS
- **Cost:** $0/month

**Option B: Vercel (Free for hobby)**
- **Free tier:** 100GB bandwidth/month, serverless functions
- **Setup:** `vercel --prod` from CLI or GitHub integration
- **Custom domain:** Free `.vercel.app` + custom domain support
- **Cost:** $0/month (hobby plan)

**Option C: Firebase Hosting (Free)**
- **Free tier:** 10GB storage, 360MB/day transfer
- **Setup:** `firebase deploy` after `flutter build web`
- **Cost:** $0/month

### Backend Services

**Option A: Railway (Free tier)**
- **Free tier:** $5 credit/month, runs 1 container
- **Suitable for:** Identity service OR relay service (not both)
- **Cost:** $0/month (with limitations)

**Option B: Fly.io (Free tier)**
- **Free tier:** 3 shared VMs, 160GB bandwidth
- **Suitable for:** All Go services on shared instances
- **Cost:** $0/month

**Option C: Render (Free tier)**
- **Free tier:** Web services spin down after inactivity
- **Suitable for:** Backend APIs with cold start tolerance
- **Cost:** $0/month

### Database

**Option A: Supabase (Free tier)**
- **Free tier:** 500MB database, 1GB file storage
- **PostgreSQL 15** with full SQL support
- **Cost:** $0/month

**Option B: Neon (Free tier)**
- **Free tier:** 512MB storage, compute auto-suspend
- **PostgreSQL 15** with branching
- **Cost:** $0/month

### Redis

**Option A: Upstash (Free tier)**
- **Free tier:** 10,000 commands/day, 256MB storage
- **Serverless Redis** — pay per request
- **Cost:** $0/month

**Option B: Redis Cloud (Free tier)**
- **Free tier:** 30MB storage, 30 connections
- **Cost:** $0/month

### Secrets Management

**Option A: Cloudflare Workers Secrets (Free)**
- Store JWT keys, salts, API keys as encrypted env vars
- **Cost:** $0/month

**Option B: Doppler (Free tier)**
- **Free tier:** 5 users, unlimited secrets
- **Cost:** $0/month

---

## Phase 2: Growth Tier ($50-200/month)

When users reach 1,000+:

| Component | Service | Cost | Why |
|-----------|---------|------|-----|
| Frontend | Vercel Pro | $20/mo | Custom domains, analytics, edge functions |
| Backend | Fly.io Scale | $50/mo | Dedicated VMs, persistent storage |
| Database | Supabase Pro | $25/mo | 8GB database, daily backups |
| Redis | Upstash Pro | $10/mo | 100K commands/day, 1GB storage |
| CDN | Cloudflare Pro | $20/mo | WAF, advanced DDoS protection |
| **Total** | | **~$125/mo** | |

---

## Phase 3: Scale Tier ($500-2000/month)

When users reach 10,000+:

| Component | Service | Cost | Why |
|-----------|---------|------|-----|
| Frontend | Vercel Enterprise | $500/mo | SLA, custom limits, SSO |
| Backend | Kubernetes (GKE/EKS) | $500/mo | Auto-scaling, rolling deploys |
| Database | PostgreSQL (managed) | $200/mo | Read replicas, point-in-time recovery |
| Redis | Redis Cluster | $100/mo | High availability, replication |
| CDN | Cloudflare Business | $200/mo | Advanced security, image optimization |
| Monitoring | Datadog/Sentry | $100/mo | APM, error tracking, uptime monitoring |
| **Total** | | **~$1,600/mo** | |

---

## Deployment Steps

### Step 1: Build Flutter Web

```bash
cd client
flutter pub get
flutter build web --release
# Output: client/build/web/
```

### Step 2: Deploy to Cloudflare Pages (Free)

```bash
# Install Wrangler CLI
npm install -g wrangler

# Login
wrangler login

# Create project
wrangler pages project create civic-commons

# Deploy
wrangler pages deploy build/web --project-name=civic-commons
```

### Step 3: Add Custom Domain

1. Go to Cloudflare Dashboard → Pages → civic-commons
2. Add custom domain: `civiccommons.org`
3. Update DNS records (Cloudflare auto-manages this)
4. SSL/TLS is automatic

### Step 4: Deploy Backend Services

```bash
# Build Docker images
docker build -t civic-commons-identity:latest -f services/cmd/identity/Dockerfile services/
docker build -t civic-commons-relay:latest -f services/cmd/relay/Dockerfile services/

# Deploy to Fly.io
flyctl auth login
flyctl launch --app civic-commons-identity
flyctl launch --app civic-commons-relay
flyctl deploy --app civic-commons-identity
flyctl deploy --app civic-commons-relay
```

### Step 5: Configure Environment Variables

```bash
# Frontend (Cloudflare Pages)
# No env vars needed — Flutter web is statically compiled

# Backend (Fly.io)
---

## Security Checklist

- [ ] All secrets in environment variables (never in code)
- [ ] HTTPS enforced everywhere (Cloudflare auto-SSL)
- [ ] CORS configured for production domains only
- [ ] Rate limiting enabled on API Gateway
- [ ] JWT RS256 validation on all authenticated endpoints
- [ ] IP stripping verified upstream
- [ ] PII scrubbing on all access logs
- [ ] SQLCipher encryption on client-side storage
- [ ] FLAG_SECURE on all sensitive screens
- [ ] Zero networking imports in domain/UI layers
- [ ] No `print()`/`debugPrint()` in production code

---

## Monitoring & Alerts

| Metric | Threshold | Action |
|--------|-----------|--------|
| Uptime | < 99.9% | Page on-call engineer |
| Response time (p95) | > 500ms | Scale backend replicas |
| Error rate | > 1% | Investigate + rollback |
| Memory usage | > 80% | Scale or restart |
| Disk usage | > 85% | Expand storage |

---

## Rollback Procedure

1. **Frontend:** Cloudflare Pages keeps previous deployments — one-click rollback
2. **Backend:** `flyctl deploy --image <previous-tag>` for instant rollback
3. **Database:** Point-in-time recovery from managed PostgreSQL backups
4. **Secrets:** Rotate via Vault — clients pick up new keys on next auth

---

## Cost Summary

| Phase | Users | Monthly Cost | Components |
|-------|-------|-------------|------------|
| Free | 0–1,000 | **$0** | Cloudflare Pages + Fly.io free + Supabase free + Upstash free |
| Growth | 1,000–10,000 | **~$125** | Vercel Pro + Fly.io Scale + Supabase Pro + Cloudflare Pro |
| Scale | 10,000+ | **~$1,600** | Vercel Enterprise + GKE + Managed PostgreSQL + Redis Cluster |
