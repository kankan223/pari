#!/usr/bin/env bash
# verify_go_deps.sh — SECURITY CHECKPOINT (Task 4.1)
#
# Confirms that NO cloud-based AI, analytics, or telemetry SDKs are present in
# the services module's Go dependencies (go.mod + go.sum).
#
# Usage: ./scripts/verify_go_deps.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES="$ROOT/services"

if [ ! -f "$SERVICES/go.mod" ]; then
  echo "ERROR: $SERVICES/go.mod not found" >&2
  exit 1
fi

# Deny-list of cloud AI / analytics / telemetry SDK import paths.
# (Comment markers `#` are not allowed in extended regex alternation for grep -E,
# so we keep this list line-based.)
DENY_LIST=(
  "opentelemetry"
  "open-telemetry"
  "datadog"
  "segmentio"
  "amplitude"
  "mixpanel"
  "sentry"
  "bugsnag"
  "rollbar"
  "newrelic"
  "posthog"
  "firebase"          # cloud SDK (analytics / app distribution)
  "google-cloud-aiplatform"
  "openai"
  "anthropic"
  "cohere"
  "gemini"            # google genai
  "langchain"
  "huggingface"
  "aws-sdk-go"        # cloud SDK (telemetry-capable)
  "azure-sdk-for-go"
  "grafana"
  "honeycomb"
  "stripe"            # payment/analytics SDK — not approved for services
  "splunk"
  "elastic"           # elasticsearch client is analytics-adjacent
)

echo "🔍 Scanning Go dependencies for cloud AI / telemetry SDKs..."
FAILED=0

for file in go.mod go.sum; do
  target="$SERVICES/$file"
  [ -f "$target" ] || continue
  for pattern in "${DENY_LIST[@]}"; do
    # Scan only module-path columns (go.sum lines are: module version hash) so
    # base64 hash bytes can never false-positive the deny-list.
    if awk '{print $1, $2}' "$target" | grep -qi "$pattern"; then
      echo "❌ FORBIDDEN dependency pattern \"$pattern\" found in $file:"
      awk '{print $1, $2}' "$target" | grep -i "$pattern" || true
      FAILED=1
    fi
  done
done

# Positive check: the five approved infra deps MUST be present in go.mod.
# A missing approved dependency is a hard failure (Task 4.1 requirement).
for dep in "go-sqlcipher" "lib/pq" "go-redis" "nats.go" "minio-go"; do
  if ! grep -q "$dep" "$SERVICES/go.mod"; then
    echo "❌ Approved dependency \"$dep\" missing from go.mod"
    FAILED=1
  fi
done

if [ "$FAILED" -ne 0 ]; then
  echo "❌ SECURITY CHECKPOINT FAILED: cloud AI / telemetry SDK present." >&2
  exit 1
fi

echo "✅ SECURITY CHECKPOINT PASSED: no cloud AI, analytics, or telemetry SDKs in Go dependencies."
