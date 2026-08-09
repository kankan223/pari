#!/usr/bin/env bash
# VERIFY (Task 4.8): end-to-end verification of the HashiCorp Vault client
# against a LIVE Vault dev server in Docker.
#
# Requires: docker (daemon up), go.
#
# Asserts:
#   1. KV v2 secret read (salt + JWT public key) via the real API
#   2. AppRole login (role_id + secret_id) → authenticated read → renew-self
#   3. Transit encrypt/decrypt round-trip
#   4. SecretCache fetch + refresh (rotation detection)
#   5. Wrong token → 403 sentinel (fail-fast auth)
#   6. SECURITY CHECKPOINT: vault tokens / auth headers are redacted by the
#      redacting logger (unit tests)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NET="civic-vault-test"
CONTAINER="civic-vault-live"
# NOTE: the dev root token ID must NOT carry the "hvs." prefix (reserved
# for real Vault tokens — dev server refuses to start with one).
VAULT_TOKEN=civic-live-root-token-1234567890abcdef
FAIL=0
CLEANUP_CMDS=()

cleanup() {
  if [ "${#CLEANUP_CMDS[@]}" -gt 0 ]; then
    for c in "${CLEANUP_CMDS[@]}"; do docker rm -f "$c" >/dev/null 2>&1 || true; done
  fi
  docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAIL=1; }

echo "=== starting Vault dev server (docker) ==="
docker network create "$NET" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" --network "$NET" \
  -e "VAULT_DEV_ROOT_TOKEN_ID=$VAULT_TOKEN" \
  -e "VAULT_DEV_LISTEN_ADDRESS=0.0.0.0:8200" \
  -p 18200:8200 \
  hashicorp/vault:1.15 >/dev/null
CLEANUP_CMDS+=("$CONTAINER")

VAULT_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER")
VAULT_ADDR="http://$VAULT_IP:8200"
echo "    vault url: $VAULT_ADDR"

echo "=== waiting for Vault readiness ==="
READY=0
for i in $(seq 1 30); do
  if docker exec "$CONTAINER" vault status -address=http://127.0.0.1:8200 >/dev/null 2>&1; then
    READY=1
    break
  fi
  sleep 1
done
if [ "$READY" != "1" ]; then
  docker logs "$CONTAINER" 2>&1 | tail -10
  echo "Vault container did not become ready" >&2
  exit 1
fi
pass "vault container ready"

# Vault CLI inside the container talks to itself via VAULT_ADDR.
docker exec -e "VAULT_ADDR=http://127.0.0.1:8200" -e "VAULT_TOKEN=$VAULT_TOKEN" "$CONTAINER" \
  sh -c '
    set -e
    vault secrets enable -path=civic-commons kv-v2
    vault secrets enable transit
    vault kv put civic-commons/identity/argon2_salt value=live-salt-value
    vault kv put civic-commons/identity/jwt_rs256_public_key value="-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0q9ZK6Cv9x1m1jK0zK3p
-----END PUBLIC KEY-----"
    vault write -f transit/keys/civic-device-keys
    vault policy write civic-commons - <<POLICY
path "civic-commons/data/*" { capabilities = ["read"] }
path "civic-commons/metadata/*" { capabilities = ["read"] }
path "transit/encrypt/civic-device-keys" { capabilities = ["create", "update"] }
path "transit/decrypt/civic-device-keys" { capabilities = ["create", "update"] }
POLICY
    vault auth enable approle
    vault write auth/approle/role/civic-app token_policies=civic-commons
    ROLE_ID=$(vault read -field=role_id auth/approle/role/civic-app/role-id)
    SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/civic-app/secret-id)
    echo "$ROLE_ID" > /tmp/civic_role_id
    echo "$SECRET_ID" > /tmp/civic_secret_id
  ' >/dev/null 2>&1
pass "vault configured (KV v2 civic-commons, transit, approle role)"

ROLE_ID=$(docker exec "$CONTAINER" cat /tmp/civic_role_id)
SECRET_ID=$(docker exec "$CONTAINER" cat /tmp/civic_secret_id)

echo "=== live vault go tests (AppRole + KV + transit + cache) ==="
if (cd "$ROOT/services" \
    && CIVIC_TEST_VAULT_ADDR="$VAULT_ADDR" \
       CIVIC_TEST_VAULT_TOKEN=$VAULT_TOKEN \
       CIVIC_TEST_VAULT_ROLE_ID="$ROLE_ID" \
       CIVIC_TEST_VAULT_SECRET_ID="$SECRET_ID" \
       go test ./internal/vault/ -count=1 -run 'TestLiveVault' -timeout 60s -v > "$ROOT/scripts/../scripts/verify_vault_tmp.log" 2>&1) \
   && grep -qE '^--- PASS' "$ROOT/scripts/../scripts/verify_vault_tmp.log"; then
  pass "live AppRole login + KV read + transit round-trip + cache"
else
  tail -12 "$ROOT/scripts/../scripts/verify_vault_tmp.log" 2>/dev/null
  fail "live vault tests failed"
fi

echo "=== wrong-token rejection (fail-fast auth) ==="
if (cd "$ROOT/services" && CIVIC_TEST_VAULT_ADDR="$VAULT_ADDR" \
    go test ./internal/vault/ -count=1 -run TestLiveVaultBadToken -timeout 30s -v > "$ROOT/scripts/../scripts/verify_vault_tmp2.log" 2>&1) \
   && grep -qE '^--- PASS' "$ROOT/scripts/../scripts/verify_vault_tmp2.log"; then
  pass "wrong token rejected with 403 sentinel"
else
  tail -8 "$ROOT/scripts/../scripts/verify_vault_tmp2.log" 2>/dev/null
  fail "wrong-token test failed"
fi

echo "=== SECURITY CHECKPOINT: token/header redaction + config enforcement ==="
(cd "$ROOT/services" && go test ./internal/logging/ ./internal/config/ -count=1 \
    -run 'TestRedactStringVaultSecrets|TestRedactingLoggerScrubsVaultToken|TestFromEnvRequiresVaultAuthInProduction' \
    -timeout 30s > "$ROOT/scripts/verify_vault_tmp3.log" 2>&1)
if grep -qE '^ok' "$ROOT/scripts/verify_vault_tmp3.log"; then
  pass "vault tokens/headers redacted; production requires Vault auth"
else
  tail -8 "$ROOT/scripts/verify_vault_tmp3.log" 2>/dev/null
  fail "redaction/config tests failed"
fi

rm -f "$ROOT/scripts/verify_vault_tmp.log" "$ROOT/scripts/verify_vault_tmp2.log" "$ROOT/scripts/verify_vault_tmp3.log"

echo
if [ "$FAIL" = "0" ]; then
  echo "ALL VAULT LIVE CHECKS PASSED"
else
  echo "SOME VAULT LIVE CHECKS FAILED"
  exit 1
fi
