#!/bin/bash
#
# Tests for the "upload" action's upload.sh.
#
# Runs upload.sh directly on the host (no Docker needed) against a one-shot
# mock HTTP server, covering the skip/success/failure paths.

set -uo pipefail

ACTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPLOAD="$ACTION_DIR/upload.sh"
MOCK="$ACTION_DIR/tests/mock-api-server.py"

PASS=0
FAIL=0

pass() { echo "✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

require() {
    command -v "$1" >/dev/null 2>&1 || { echo "❌ Required tool not found: $1"; exit 2; }
}

require curl
require python3

# A small sample SBOM to upload.
SAMPLE="$(mktemp)"
cat > "$SAMPLE" <<'EOF'
{"componentCount":1,"components":[{"name":"lodash","version":"4.17.21","purl":"pkg:npm/lodash@4.17.21","type":"library","group":""}]}
EOF

# run_upload <mock-status> <api-key> <sbom-file> -> sets BODY/HDR/UPLOAD_RC.
run_upload() {
    local mock_status=$1 api_key=$2 sbom_file=$3
    BODY="$(mktemp)"; HDR="$(mktemp)"; local portfile; portfile="$(mktemp)"
    python3 "$MOCK" "$BODY" "$HDR" "$mock_status" >"$portfile" 2>/dev/null &
    local mock_pid=$!
    local port=""
    for _ in $(seq 1 25); do port="$(cat "$portfile" 2>/dev/null)"; [ -n "$port" ] && break; sleep 0.2; done
    rm -f "$portfile"
    if [ -z "$port" ]; then UPLOAD_RC=99; kill "$mock_pid" 2>/dev/null; return; fi

    SBOM_FILE="$sbom_file" \
    API_URL="http://127.0.0.1:$port" \
    API_KEY="$api_key" \
        bash "$UPLOAD" >/tmp/upload.log 2>&1
    UPLOAD_RC=$?
    # The mock exits after one request (or its timeout); reap it without hanging.
    wait "$mock_pid" 2>/dev/null
}

echo "=========================================="
echo " upload action test suite"
echo "=========================================="

# ---- Test: empty api-url skips upload ------------------------------------
echo "▶ Empty api-url skips upload"
if SBOM_FILE="$SAMPLE" API_URL="" API_KEY="" bash "$UPLOAD" >/tmp/skip.log 2>&1; then
    if grep -qi "skipping API upload" /tmp/skip.log && ! grep -qi "Uploading" /tmp/skip.log; then
        pass "empty api-url skips upload and exits 0"
    else
        fail "empty api-url did not skip"; cat /tmp/skip.log
    fi
else
    fail "empty api-url should exit 0"; cat /tmp/skip.log
fi

# ---- Test: whitespace-only api-url skips upload ---------------------------
echo "▶ Whitespace-only api-url skips upload"
if SBOM_FILE="$SAMPLE" API_URL="   " bash "$UPLOAD" >/tmp/skip2.log 2>&1 \
    && grep -qi "skipping API upload" /tmp/skip2.log; then
    pass "whitespace api-url skips upload"
else
    fail "whitespace api-url did not skip"; cat /tmp/skip2.log
fi

# ---- Test: missing SBOM file fails ---------------------------------------
echo "▶ Missing SBOM file is rejected"
if SBOM_FILE="/no/such/sbom.json" API_URL="http://127.0.0.1:1" bash "$UPLOAD" >/tmp/nofile.log 2>&1; then
    fail "missing SBOM file should exit non-zero"
else
    grep -qi "not found" /tmp/nofile.log \
        && pass "missing SBOM file exits non-zero with message" \
        || { fail "missing SBOM file wrong error"; cat /tmp/nofile.log; }
fi

# ---- Test: successful upload (2xx) ---------------------------------------
echo "▶ Upload succeeds on 2xx"
run_upload 200 "test-key-123" "$SAMPLE"
if [ "$UPLOAD_RC" -eq 0 ]; then
    pass "upload.sh exits 0 on 2xx"
else
    fail "upload.sh failed on 2xx (rc=$UPLOAD_RC)"; cat /tmp/upload.log
fi
if [ "$(jq -r '.components[0].purl' "$BODY" 2>/dev/null)" = "pkg:npm/lodash@4.17.21" ]; then
    pass "API received the SBOM as the POST body"
else
    fail "API did not receive the expected SBOM body"
fi
if head -n1 "$HDR" 2>/dev/null | grep -q "test-key-123"; then
    pass "API received the X-Api-Key header"
else
    fail "API did not receive the X-Api-Key header"
fi
rm -f "$BODY" "$HDR"

# ---- Test: failed upload (5xx) -------------------------------------------
echo "▶ Upload fails on 5xx"
run_upload 500 "test-key-123" "$SAMPLE"
if [ "$UPLOAD_RC" -ne 0 ] && [ "$UPLOAD_RC" -ne 99 ]; then
    pass "upload.sh exits non-zero on 5xx"
else
    fail "upload.sh did not fail on 5xx (rc=$UPLOAD_RC)"; cat /tmp/upload.log
fi
rm -f "$BODY" "$HDR"

rm -f "$SAMPLE"

# ---- Summary --------------------------------------------------------------
echo "=========================================="
echo " Results: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ]
