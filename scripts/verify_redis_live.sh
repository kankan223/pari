#!/usr/bin/env bash
# VERIFY (Task 4.6): end-to-end verification of the Redis configuration
# against a LIVE Redis 7 Sentinel cluster (1 primary + 2 replicas + 3
# sentinels) in Docker.
#
# Requires: docker (daemon up), go.
#
# Asserts:
#   1. Standalone client: set/get, TTL expiry (key deleted), stream XTRIM
#      MINID age eviction + purge-on-drain (go tests, unit + live)
#   2. Connection pool starvation/recovery (go test, live)
#   3. Sentinel HA: client resolves the elected master and round-trips
#   4. FAILOVER: killing the primary promotes a replica; the go-redis
#      failover client transparently follows the new master
#   5. AOF + RDB persistence config is present (redis.conf check)
#   6. SECURITY CHECKPOINT: namespace key builders reject PII-shaped
#      suffixes (no raw phone / raw OTP can become a Redis key)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NET="civic-redis-test"
WORK="$(mktemp -d /tmp/redis-live.XXXXXX)"
FAIL=0
CLEANUP_CMDS=()

cleanup() {
  if [ "${#CLEANUP_CMDS[@]}" -gt 0 ]; then
    for c in "${CLEANUP_CMDS[@]}"; do docker rm -f "$c" >/dev/null 2>&1 || true; done
  fi
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }

echo "=== starting Redis Sentinel cluster (docker) ==="
docker network create "$NET" >/dev/null 2>&1 || true

# The test cluster runs WITHOUT a password so the env-gated Go tests
# (which build clients from a bare address) can connect directly.
start_node() { # name, extra-args...
  local name="$1"; shift
  docker run -d --name "$name" --network "$NET" \
    redis:7-alpine redis-server \
    --appendonly yes --appendfsync everysec --save '3600 1 300 100 60 10000' \
    --maxmemory-policy noeviction "$@" >/dev/null
  CLEANUP_CMDS+=("$name")
}

start_node civic-redis-master
MASTER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' civic-redis-master)

start_node civic-redis-replica-1 --replicaof "$MASTER_IP" 6379
start_node civic-redis-replica-2 --replicaof "$MASTER_IP" 6379

# Three sentinels monitoring the primary (quorum 2). Sentinel requires a
# WRITABLE config file (it persists its own state by rewriting the file), so
# write one per node, mount it, and copy it to a writable location first.
for i in 1 2 3; do
  SENT_CONF="$WORK/sentinel-$i.conf"
  cat > "$SENT_CONF" <<EOF
port 26379
dir /data
sentinel monitor civic-master $MASTER_IP 6379 2
sentinel down-after-milliseconds civic-master 2000
sentinel failover-timeout civic-master 5000
sentinel parallel-syncs civic-master 1
EOF
  docker run -d --name "civic-redis-sentinel-$i" --network "$NET" \
    -v "$SENT_CONF:/conf/sentinel.conf:ro" \
    redis:7-alpine sh -c 'cp /conf/sentinel.conf /data/sentinel.conf && exec redis-server /data/sentinel.conf --sentinel' >/dev/null
  CLEANUP_CMDS+=("civic-redis-sentinel-$i")
done

echo "=== waiting for cluster readiness ==="
MASTER_ADDR=""
for i in $(seq 1 30); do
  MASTER_ADDR=$(docker exec civic-redis-sentinel-1 redis-cli -p 26379 \
    sentinel get-master-addr-by-name civic-master 2>/dev/null | tr '\n' ' ' | awk '{print $1":"$2}')
  [ -n "$MASTER_ADDR" ] && [ "$MASTER_ADDR" != ":" ] && break
  sleep 1
done
if [ -z "$MASTER_ADDR" ] || [ "$MASTER_ADDR" = ":" ]; then
  fail "sentinel did not report a master"
  docker ps --format '{{.Names}} {{.Status}}' | grep civic-redis || true
  exit 1
fi
pass "sentinel reports master at $MASTER_ADDR"

# The Go client runs on the host; the Docker bridge is directly reachable
# via each container's network IP, so no port publishing is needed.
SENTINEL_ADDRS=""
for i in 1 2 3; do
  SENTINEL_ADDRS="$SENTINEL_ADDRS,$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' civic-redis-sentinel-$i):26379"
done
SENTINEL_ADDRS="${SENTINEL_ADDRS#,}"

echo "=== live Go tests (standalone + sentinel) ==="
cd "$ROOT/services"
RUN="go test ./internal/cache/ -count=1 -run 'TestLive|TestNewClient|TestKeyExpiry|TestStreamTrimAndPurge|TestNamespace|TestTTL|TestKeyBuilders|TestFamily|TestVoteBuffer|TestValidate' -v"
OUT=$(CIVIC_TEST_REDIS_ADDR="$MASTER_ADDR" CIVIC_TEST_REDIS_SENTINEL_ADDRS="$SENTINEL_ADDRS" eval "$RUN" 2>&1)
echo "$OUT" | grep -E '^(--- PASS|--- FAIL|--- SKIP|PASS|FAIL|ok)' | head -40
if echo "$OUT" | grep -q -- '--- FAIL'; then
  fail "live cache tests failed"
else
  pass "live cache tests (pool starvation/recovery, TTL expiry, stream purge, sentinel round-trip)"
fi

echo "=== FAILOVER: killing the primary ==="
docker rm -f civic-redis-master >/dev/null 2>&1
# Sentinel must promote a replica within down-after (2s) + failover timeout (5s).
PROMOTED=""
for i in $(seq 1 30); do
  PROMOTED=$(docker exec civic-redis-sentinel-1 redis-cli -p 26379 \
    sentinel get-master-addr-by-name civic-master 2>/dev/null | tr '\n' ' ' | awk '{print $1":"$2}')
  [ -n "$PROMOTED" ] && [ "$PROMOTED" != ":" ] && [ "${PROMOTED%%:*}" != "$MASTER_IP" ] && break
  sleep 1
done
if [ -z "$PROMOTED" ] || [ "$PROMOTED" = ":" ] || [ "${PROMOTED%%:*}" = "$MASTER_IP" ]; then
  fail "no failover: sentinel still points at dead primary ($PROMOTED)"
else
  pass "failover: sentinel promoted new master at $PROMOTED"
fi

echo "=== post-failover live Sentinel test (client must follow promotion) ==="
OUT2=$(CIVIC_TEST_REDIS_SENTINEL_ADDRS="$SENTINEL_ADDRS" CIVIC_TEST_REDIS_MASTER="civic-master" \
  go test ./internal/cache/ -count=1 -run 'TestLiveSentinelFailover' -v 2>&1)
echo "$OUT2" | grep -E '^(--- PASS|--- FAIL|--- SKIP|ok|FAIL)' | head -5
if echo "$OUT2" | grep -q -- '--- PASS: TestLiveSentinelFailover'; then
  pass "client continues to write/read through Sentinel after failover"
else
  fail "post-failover client test failed"
fi

echo "=== AOF + RDB persistence config present ==="
CONF=$(docker exec civic-redis-replica-1 redis-cli config get appendonly 2>/dev/null | tail -1)
if [ "$CONF" = "yes" ]; then pass "AOF enabled (appendonly=yes)"; else fail "AOF not enabled"; fi
RDB=$(docker exec civic-redis-replica-1 redis-cli config get save 2>/dev/null | tail -1)
if echo "$RDB" | grep -q '3600'; then pass "RDB save points configured"; else fail "RDB save points missing"; fi

echo ""
if [ "$FAIL" = "1" ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: ALL CHECKS PASSED"
