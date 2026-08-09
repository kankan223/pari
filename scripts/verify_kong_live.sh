#!/usr/bin/env bash
# VERIFY (Task 4.2): end-to-end test of the Kong OSS 3.x gateway declarative
# configuration against a LIVE Kong container (DB-less mode).
#
# Requires: docker (daemon up), openssl, python3. Optional: lua.
#
# Asserts:
#   1. JWT: no token        -> 401
#   2. JWT: tampered token  -> 401
#   3. JWT: valid RS256     -> 200
#   4. Rate limiting: burst beyond limit -> 429, keyed PER blind_hash_id
#      (consumer A throttled while consumer B still passes)
#   5. SECURITY CHECKPOINT: upstream receives NO X-Forwarded-For (strip
#      plugin) and NO client-derived X-Real-IP (peer address only)
#   6. response-transformer: no Server / Via headers downstream
#   7. correlation-id: Kong-Request-ID present downstream
#   8. PII scrub: access log (custom plugin) redacts phone numbers / client IPs
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KONG_YAML="$ROOT/infrastructure/helm/kong/files/kong.yaml"
SCRUBBER="$ROOT/infrastructure/helm/kong/files/pii_scrubber.lua"
PLUGIN_DIR="$ROOT/infrastructure/helm/kong/files/plugins/civic-pii-access-log"
STRIP_DIR="$ROOT/infrastructure/helm/kong/files/plugins/civic-strip-peer-ip"
WORK="$(mktemp -d /tmp/kong-live.XXXXXX)"
FAIL=0
KONG_CT="kong-live-test"
UP_PID=""

cleanup() {
  [ -n "$UP_PID" ] && kill "$UP_PID" 2>/dev/null || true
  docker rm -f "$KONG_CT" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }
expect_code() { # desc, expected, actual
  if [ "$2" = "$3" ]; then pass "$1 (HTTP $3)"; else fail "$1 (expected $2, got $3)"; fi
}

echo "=== preparing mock upstream + keys ==="
cat > "$WORK/upstream.py" <<PY
import http.server
# append mode: the harness truncates the log before each capture (`: >`),
# and append mode keeps the file position at EOF so no NUL padding
# accumulates after truncation.
LOG = open('$WORK/upstream.log', 'a')
class H(http.server.BaseHTTPRequestHandler):
    def _h(self):
        LOG.write(str(self.headers))
        LOG.flush()
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ok')
    do_GET = do_POST = do_PUT = do_DELETE = _h
    def log_message(self, *a):
        pass
http.server.HTTPServer(('0.0.0.0', 19099), H).serve_forever()
PY
nohup python3 "$WORK/upstream.py" >/dev/null 2>&1 &
UP_PID=$!
sleep 1

openssl genrsa -out "$WORK/private.pem" 2048 2>/dev/null
openssl rsa -in "$WORK/private.pem" -pubout -out "$WORK/public.pem" 2>/dev/null
GW=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || echo 172.17.0.1)

echo "=== building runtime kong.yml (from files/kong.yaml) ==="
python3 - "$KONG_YAML" "$WORK" "$GW" <<'PY'
import sys, yaml

cfg = yaml.safe_load(open(sys.argv[1]))
work, gw = sys.argv[2], sys.argv[3]
pub = open(work + "/public.pem").read()

# 1) point the upstream at the local echo server
cfg["services"][0]["url"] = "http://%s:19099" % gw

# 2) inject two test consumers (per-blind_hash_id rate-limit isolation)
cfg["consumers"] = [
    {"username": "blindhash123",
     "jwt_secrets": [{"key": "probe", "algorithm": "RS256", "rsa_public_key": pub}]},
    {"username": "blindhash456",
     "jwt_secrets": [{"key": "probe2", "algorithm": "RS256", "rsa_public_key": pub}]},
]

# 3) tighten rate limit to 3 req/sec so throttling is provable fast
for p in cfg.get("plugins", []):
    if p["name"] == "rate-limiting":
        p["config"]["second"] = 3

yaml.safe_dump(cfg, open(work + "/runtime.yml", "w"), sort_keys=False)
print("runtime.yml written (upstream=%s)" % gw)
PY

echo "=== starting Kong (DB-less) ==="
docker run -d --name "$KONG_CT" -p 8000:8000 \
  -v "$WORK/runtime.yml:/kong/declarative/kong.yml" \
  -v "$SCRUBBER:/usr/local/share/lua/5.1/civic/pii_scrubber.lua:ro" \
  -v "$PLUGIN_DIR:/usr/local/share/lua/5.1/kong/plugins/civic-pii-access-log:ro" \
  -v "$STRIP_DIR:/usr/local/share/lua/5.1/kong/plugins/civic-strip-peer-ip:ro" \
  -e KONG_DATABASE=off \
  -e KONG_DECLARATIVE_CONFIG=/kong/declarative/kong.yml \
  -e KONG_LUA_PACKAGE_PATH="/usr/local/share/lua/5.1/?.lua;;" \
  -e KONG_PLUGINS=bundled,civic-pii-access-log,civic-strip-peer-ip \
  -e KONG_HEADERS=latency_tokens \
  -e KONG_PROXY_ACCESS_LOG=off \
  -e KONG_LOG_LEVEL=notice \
  kong:3.8 >/dev/null

READY=0
for i in $(seq 1 120); do
  if curl -s -o /dev/null http://localhost:8000/x 2>/dev/null; then READY=1; break; fi
  sleep 1
done
if [ "$READY" -ne 1 ]; then
  echo "FAIL  Kong did not become ready; logs:"
  docker logs "$KONG_CT" 2>&1 | tail -20
  exit 1
fi
pass "Kong started and accepts connections"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
sign_token() { # kid, sub
  local H P SIG
  H=$(printf '{"alg":"RS256","typ":"JWT","kid":"%s"}' "$1" | b64url)
  P=$(printf '{"sub":"%s","exp":%d}' "$2" $(( $(date +%s) + 3600 )) | b64url)
  SIG=$(printf '%s.%s' "$H" "$P" | openssl dgst -sha256 -sign "$WORK/private.pem" -binary | b64url)
  echo "$H.$P.$SIG"
}
TOKEN_A=$(sign_token probe blindhash123)
TOKEN_B=$(sign_token probe2 blindhash456)

echo "=== 1) JWT validation ==="
expect_code "no token rejected"      401 "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/v1/ping)"
expect_code "tampered token rejected" 401 "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/v1/ping -H "Authorization: Bearer ${TOKEN_A}x")"
expect_code "valid RS256 token accepted" 200 "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/v1/ping -H "Authorization: Bearer $TOKEN_A")"

echo "=== 2) rate limiting (3/sec, per blind_hash_id) ==="
A_CODES=""
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  A_CODES="$A_CODES $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/v1/ping -H "Authorization: Bearer $TOKEN_A")"
done
OK_A=$(echo "$A_CODES" | tr ' ' '\n' | grep -c '^200$' || true)
RL_A=$(echo "$A_CODES" | tr ' ' '\n' | grep -c '^429$' || true)
echo "  consumer A codes:$A_CODES (200=$OK_A, 429=$RL_A)"
[ "$RL_A" -ge 1 ] && pass "consumer A: burst throttled with 429" || fail "consumer A: no 429 observed in 12-request burst"
[ "$OK_A" -le 6 ] && pass "consumer A: requests allowed stay within a reasonable bound ($OK_A <= 6)" || fail "consumer A: $OK_A requests allowed (bound exceeded)"

# per-consumer isolation: B must still pass while A is throttled
expect_code "consumer B unaffected by A's limit (per blind_hash_id)" 200 \
  "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/v1/ping -H "Authorization: Bearer $TOKEN_B")"

echo "=== 3) response headers (transformer + correlation-id) ==="
HDRS=$(curl -s -D - -o /dev/null http://localhost:8000/v1/ping -H "Authorization: Bearer $TOKEN_B")
if echo "$HDRS" | grep -qi '^kong-request-id:'; then pass "correlation-id Kong-Request-ID present"; else fail "correlation-id missing"; fi
if echo "$HDRS" | grep -qiE '^server:|^via:'; then fail "Server/Via headers NOT stripped: $(echo "$HDRS" | grep -iE '^server:|^via:' | tr '\n' ' ')"; else pass "Server/Via headers stripped"; fi

echo "=== 4) SECURITY CHECKPOINT: IP stripping upstream ==="
sleep 1.2  # let the rate-limit window reset for a clean upstream capture
: > "$WORK/upstream.log"   # clean slate — only the probe request below is captured
curl -s -o /dev/null http://localhost:8000/v1/ping -H "Authorization: Bearer $TOKEN_B" -H "X-Forwarded-For: 203.0.113.66" -H "X-Real-IP: 203.0.113.66"
sleep 0.5
if grep -aqi '^X-Forwarded-For:' "$WORK/upstream.log"; then
  fail "X-Forwarded-For reached upstream"; grep -ai 'x-forwarded-for' "$WORK/upstream.log" | head -1
else
  pass "X-Forwarded-For header absent upstream (civic-strip-peer-ip)"
fi
if grep -aqi '203\.0\.113\.66' "$WORK/upstream.log"; then
  fail "client IP 203.0.113.66 reached upstream in a header"
else
  pass "client-supplied IPs never reach upstream"
fi
XREAL=$(grep -ai '^X-Real-IP:' "$WORK/upstream.log" | tail -1 | tr -d '\r' | awk '{print $2}')
if [ -z "$XREAL" ]; then
  pass "X-Real-IP absent upstream"
elif [ "$XREAL" = "$GW" ]; then
  pass "X-Real-IP carries only the trusted peer address ($GW) — Kong template hardcode; never client-derived"
else
  fail "X-Real-IP unexpected value: $XREAL"
fi

echo "=== 5) PII scrubbing in access logs (custom plugin) ==="
sleep 1.2
curl -s -o /dev/null "http://localhost:8000/v1/ping?phone=%2B14155552671&from=203.0.113.99" -H "Authorization: Bearer $TOKEN_B"
sleep 1
LOGS=$(docker logs "$KONG_CT" 2>&1)
if echo "$LOGS" | grep -q '\[REDACTED\]'; then
  pass "access log contains [REDACTED] markers"
else
  fail "no [REDACTED] markers found in access log"
fi
if echo "$LOGS" | grep -q '14155552671'; then
  fail "raw phone number leaked into access log"
else
  pass "phone number redacted from access log"
fi
if echo "$LOGS" | grep -q '203\.0\.113\.99'; then
  fail "client IP leaked into access log"
else
  pass "client IP redacted from access log"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "VERIFY KONG GATEWAY (live): ALL PASS"
  exit 0
else
  echo "VERIFY KONG GATEWAY (live): FAILURES"
  exit 1
fi
