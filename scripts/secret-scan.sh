#!/bin/bash
# Civic Commons Secret Scanning Script
# This script performs basic secret detection using grep patterns
# For production, install gitleaks: https://github.com/gitleaks/gitleaks

set -e

echo "🔍 Running secret scanning..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Patterns to detect
PATTERNS=(
    "sk_test_[a-zA-Z0-9]{20,}"
    "sk_live_[a-zA-Z0-9]{20,}"
    "AIza[0-9A-Za-z\-_]{35}"
    "AKIA[0-9A-Z]{16}"
    "[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+:[a-zA-Z0-9._-]+"
    "password\s*[:=]\s*['\"][a-zA-Z0-9._-]{8,}['\"]"
    "api[_-]?key\s*[:=]\s*['\"][a-zA-Z0-9._-]{20,}['\"]"
    "secret\s*[:=]\s*['\"][a-zA-Z0-9._-]{20,}['\"]"
    "token\s*[:=]\s*['\"][a-zA-Z0-9._-]{20,}['\"]"
    "private[_-]?key\s*[:=]\s*['\"][a-zA-Z0-9+/]{40,}['\"]"
    "-----BEGIN.*PRIVATE KEY-----"
    "civic_api_key"
    "vault_token"
)

# Directories to exclude
EXCLUDE_DIRS=(
    "node_modules"
    ".git"
    "build"
    "dist"
    "vendor"
    ".terraform"
    "coverage"
    ".dart_tool"
    ".flutter-plugins"
)

# Build exclude pattern
EXCLUDE_PATTERN=""
for dir in "${EXCLUDE_DIRS[@]}"; do
    EXCLUDE_PATTERN="$EXCLUDE_PATTERN --exclude-dir=$dir"
done
# Also exclude the script itself
EXCLUDE_PATTERN="$EXCLUDE_PATTERN --exclude=secret-scan.sh"

# Track if secrets found
SECRETS_FOUND=0

# Scan for each pattern
for pattern in "${PATTERNS[@]}"; do
    echo -n "  Checking pattern: ${pattern:0:50}... "
    
    # Run grep with the pattern
    if grep -r -i -n "$pattern" . $EXCLUDE_PATTERN 2>/dev/null; then
        echo -e "${RED}FOUND${NC}"
        SECRETS_FOUND=1
    else
        echo -e "${GREEN}OK${NC}"
    fi
done

# Check for specific high-risk files
echo -n "  Checking for high-risk files (.key, .pem, .env)... "
if find . -type f \( -name "*.key" -o -name "*.pem" -o -name ".env" -o -name "*.env.*" \) $EXCLUDE_PATTERN 2>/dev/null | grep -q .; then
    echo -e "${RED}FOUND${NC}"
    find . -type f \( -name "*.key" -o -name "*.pem" -o -name ".env" -o -name "*.env.*" \) $EXCLUDE_PATTERN 2>/dev/null
    SECRETS_FOUND=1
else
    echo -e "${GREEN}OK${NC}"
fi

# Final result
if [ $SECRETS_FOUND -eq 1 ]; then
    echo -e "\n${RED}❌ Secret scanning failed. Potential secrets detected.${NC}"
    echo "Please remove or redact any sensitive data before committing."
    exit 1
else
    echo -e "\n${GREEN}✅ Secret scanning passed - no secrets detected${NC}"
    exit 0
fi
