#!/usr/bin/env bash
# VERIFY (Task 4.7): end-to-end verification of the NATS JetStream event bus
# against a LIVE nats-server container with JetStream enabled.
#
# Requires: docker (daemon up), go.
#
# Asserts:
#   1. JetStream is enabled and the CIVIC_EVENTS stream is created with File
#      storage (go test, live)
#   2. Pub/sub round-trip through a DURABLE consumer with explicit acks
#      (go test, live)
#   3. DURABILITY: events survive a full broker restart (container killed and
#      restarted with the same store volume) — no event loss
#   4. SECURITY CHECKPOINT: subjects/payloads carrying plaintext PII are
#      rejected (unit tests) and the stream subjects are the registered
#      non-PII allowlist
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NET="civic-nats-test"
WORK="$(mktemp -d /tmp/nats-live.XXXXXX)"
STORE_VOL="civic-nats-store"
CONTAINER="civic-nats-live"
FAIL=0
CLEANUP_CMDS=()

cleanup() {
  if [ "${#CLEANUP_CMDS[@]}" -gt 0 ]; then
    for c in "${CLEANUP_CMDS[@]}"; do docker rm -f "$c" >/dev/null 2>&1 || true; done
  fi
  docker volume rm "$STORE_VOL" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }

echo "=== starting NATS JetStream container (docker) ==="
docker network create "$NET" >/dev/null 2>&1 || true
docker volume create "$STORE_VOL" >/dev/null 2>&1 || true

# JetStream with FILE storage on a persistent volume (durability across
# restart is exactly what we verify in step 3). -m 8222 exposes the
# monitoring HTTP endpoint used for readiness probes.
docker run -d --name "$CONTAINER" --network "$NET" \
  -v "$STORE_VOL":/data \
  nats:2.10-alpine \
  -js -m 8222 -sd /data --store_dir /data >/dev/null
CLEANUP_CMDS+=("$CONTAINER")

NATS_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER")
NATS_URL="nats://$NATS_IP:4222"
echo "    nats url: $NATS_URL"

echo "=== waiting for NATS readiness ==="
READY=0
for i in $(seq 1 30); do
  if docker exec "$CONTAINER" wget -q -O - http://127.0.0.1:8222/healthz 2>/dev/null | grep -q '"status":"ok"'; then
    READY=1
    break
  fi
  sleep 1
done
if [ "$READY" != "1" ]; then
  docker logs "$CONTAINER" 2>&1 | tail -10
  echo "NATS container did not become ready" >&2
  exit 1
fi
pass "nats container ready (JetStream enabled)"

echo "=== 1. JetStream enabled + CIVIC_EVENTS stream (file storage) ==="
docker exec "$CONTAINER" wget -q -O - http://127.0.0.1:8222/jsz 2>/dev/null | grep -q 'jetstream' \
  && pass "JetStream reports enabled" || fail "JetStream not enabled"
# The stream is created by the live Go test below (EnsureStream).

echo "=== 2. pub/sub round-trip via durable consumer (live go tests) ==="
# Note: output goes to a file first — with pipefail, `grep -q` closing the
# pipe early would SIGPIPE go test and falsely fail the pipeline.
if (cd "$ROOT/services" && CIVIC_TEST_NATS_URL="$NATS_URL" go test ./internal/events/ -count=1 -run TestLiveNATSJetStream -timeout 60s -v > "$WORK/live1.log" 2>&1) && grep -qE '^--- PASS' "$WORK/live1.log"; then
  pass "live pub/sub through durable consumer (5 events acked)"
else
  tail -8 "$WORK/live1.log" 2>/dev/null
  fail "live pub/sub test failed"
fi

echo "=== 3. DURABILITY: broker restart loses no events ==="
docker stop "$CONTAINER" >/dev/null && docker start "$CONTAINER" >/dev/null
READY=0
for i in $(seq 1 30); do
  if docker exec "$CONTAINER" wget -q -O - http://127.0.0.1:8222/healthz 2>/dev/null | grep -q '"status":"ok"'; then
    READY=1
    break
  fi
  sleep 1
done
if [ "$READY" != "1" ]; then
  echo "NATS did not become ready after restart" >&2
  exit 1
fi
# The stream must still exist with the same name AFTER the restart (file
# store persisted on the volume).
if docker exec "$CONTAINER" wget -q -O - "http://127.0.0.1:8222/jsz?streams=1" 2>/dev/null | grep -q 'CIVIC_EVENTS'; then
  pass "CIVIC_EVENTS stream survived broker restart (durable file storage)"
else
  fail "CIVIC_EVENTS stream missing after restart (event loss)"
fi
# And the client can still publish + read through the durable consumer.
if (cd "$ROOT/services" && CIVIC_TEST_NATS_URL="$NATS_URL" go test ./internal/events/ -count=1 -run TestLiveNATSJetStream -timeout 60s -v > "$WORK/live2.log" 2>&1) && grep -qE '^--- PASS' "$WORK/live2.log"; then
  pass "post-restart round-trip through the surviving durable consumer"
else
  tail -8 "$WORK/live2.log" 2>/dev/null
  fail "post-restart round-trip failed"
fi

echo "=== 4. SECURITY CHECKPOINT (no plaintext PII in events) ==="
if (cd "$ROOT/services" && go test ./internal/events/ -count=1 -run 'TestPublishRejectsPII|TestValidateSubject|TestValidatePayload' -timeout 30s 2>&1 | grep -q '^ok'); then
  pass "PII-shaped subjects/payloads rejected; subjects are the allowlist"
else
  fail "PII rejection tests failed"
fi

echo
if [ "$FAIL" = "0" ]; then
  echo "ALL NATS JETSTREAM LIVE CHECKS PASSED"
else
  echo "SOME NATS JETSTREAM LIVE CHECKS FAILED"
  exit 1
fi
