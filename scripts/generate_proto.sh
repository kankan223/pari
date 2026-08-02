#!/usr/bin/env bash
# generate_proto.sh — regenerate protobuf Go code for the services module.
#
# Usage: ./scripts/generate_proto.sh
# Requires: protoc, protoc-gen-go (pinned via services/tools.go).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICES="$ROOT/services"

if ! command -v protoc >/dev/null 2>&1; then
  echo "ERROR: protoc is not installed" >&2
  exit 1
fi

if ! command -v protoc-gen-go >/dev/null 2>&1; then
  echo "ERROR: protoc-gen-go is not on PATH" >&2
  echo "Install the pinned version: go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.35.2" >&2
  exit 1
fi

echo "Regenerating protobuf code in $SERVICES..."
(cd "$SERVICES" && go generate ./proto)
echo "Done."
