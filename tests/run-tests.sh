#!/bin/bash
#
# Integration tests for the Rakuten Maritime SBOM action.
#
# Builds the Docker image and drives it through its real entrypoint the same way
# GitHub Actions does, asserting on the generated SBOMs for each supported
# format as well as the error paths.
#
# Usage:
#   tests/run-tests.sh              # build image, then run tests
#   IMAGE=my:tag tests/run-tests.sh # reuse an already-built image (skip build)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$REPO_ROOT/tests/fixtures/npm-project"
IMAGE="${IMAGE:-maritime-sbom-action:test}"
PLATFORM="${PLATFORM:-linux/amd64}"

PASS=0
FAIL=0

pass() { echo "✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

# Require a command, otherwise abort the whole suite.
require() {
    command -v "$1" >/dev/null 2>&1 || { echo "❌ Required tool not found: $1"; exit 2; }
}

require docker
require jq

# Run the action image against $FIXTURE in an isolated work dir.
#   run_action <format> <output-file>  -> stdout+stderr, exit code preserved
# The generated SBOM is left in $WORKDIR for the caller to inspect.
WORKDIR=""
run_action() {
    local format=$1 output=$2 scan_path=${3:-.}
    WORKDIR="$(mktemp -d)"
    cp -R "$FIXTURE/." "$WORKDIR/"
    : > "$WORKDIR/gh_output"
    docker run --rm --platform "$PLATFORM" \
        -e GITHUB_OUTPUT=/github/workspace/gh_output \
        -v "$WORKDIR:/github/workspace" \
        "$IMAGE" "$scan_path" "$format" "$output"
}

echo "=========================================="
echo " Rakuten Maritime SBOM action test suite"
echo "=========================================="

# ---- Build ----------------------------------------------------------------
if [ -n "${IMAGE_PREBUILT:-}" ] || [ "${SKIP_BUILD:-}" = "1" ]; then
    echo "▶ Skipping build, using image: $IMAGE"
else
    echo "▶ Building image: $IMAGE"
    if docker build --platform "$PLATFORM" -t "$IMAGE" "$REPO_ROOT" >/dev/null 2>&1; then
        pass "docker image builds"
    else
        fail "docker image builds"
        echo "Build failed; aborting."
        exit 1
    fi
fi

# ---- Test: CycloneDX ------------------------------------------------------
echo "▶ CycloneDX generation"
if run_action cyclonedx sbom.json >/tmp/cdx.log 2>&1; then
    out="$WORKDIR/sbom.json"
    if [ -f "$out" ] \
        && [ "$(jq -r '.bomFormat' "$out")" = "CycloneDX" ] \
        && [ "$(jq '[.components[]? | select(.name=="lodash")] | length' "$out")" -ge 1 ]; then
        pass "cyclonedx SBOM has bomFormat=CycloneDX and includes lodash"
    else
        fail "cyclonedx SBOM missing expected content"; cat /tmp/cdx.log
    fi
    grep -q "sbom-file=sbom.json" "$WORKDIR/gh_output" \
        && pass "cyclonedx sets sbom-file GitHub output" \
        || fail "cyclonedx did not set sbom-file output"
else
    fail "cyclonedx run exited non-zero"; cat /tmp/cdx.log
fi
rm -rf "$WORKDIR"

# ---- Test: unsupported format fails --------------------------------------
echo "▶ Unsupported format is rejected"
if run_action spdx sbom.json >/tmp/bad.log 2>&1; then
    fail "unsupported format should exit non-zero"
else
    grep -qi "Unsupported format" /tmp/bad.log \
        && pass "unsupported format exits non-zero with message" \
        || { fail "unsupported format wrong error"; cat /tmp/bad.log; }
fi
rm -rf "$WORKDIR"

# ---- Test: missing scan path fails ---------------------------------------
echo "▶ Missing scan path is rejected"
if run_action cyclonedx sbom.json ./does-not-exist >/tmp/missing.log 2>&1; then
    fail "missing scan path should exit non-zero"
else
    grep -qi "does not exist" /tmp/missing.log \
        && pass "missing scan path exits non-zero with message" \
        || { fail "missing scan path wrong error"; cat /tmp/missing.log; }
fi
rm -rf "$WORKDIR"

# ---- Test: API upload -----------------------------------------------------
# Spin up a one-shot mock HTTP server on the host and point the action at it
# via host.docker.internal, asserting the SBOM body and X-Api-Key header are
# received, and that a 5xx response makes the action fail.
run_upload() {
    # run_upload <mock-status> <api-key> -> exports PORT/BODY/HDR, runs action,
    # sets UPLOAD_RC to the action exit code.
    local mock_status=$1 api_key=$2
    BODY="$(mktemp)"; HDR="$(mktemp)"; local portfile; portfile="$(mktemp)"
    python3 "$REPO_ROOT/tests/mock-api-server.py" "$BODY" "$HDR" "$mock_status" >"$portfile" 2>/dev/null &
    local mock_pid=$!
    PORT=""
    for _ in $(seq 1 25); do PORT="$(cat "$portfile" 2>/dev/null)"; [ -n "$PORT" ] && break; sleep 0.2; done
    rm -f "$portfile"
    if [ -z "$PORT" ]; then UPLOAD_RC=99; kill "$mock_pid" 2>/dev/null; return; fi

    WORKDIR="$(mktemp -d)"; cp -R "$FIXTURE/." "$WORKDIR/"; : > "$WORKDIR/gh_output"
    docker run --rm --platform "$PLATFORM" \
        --add-host=host.docker.internal:host-gateway \
        -e GITHUB_OUTPUT=/github/workspace/gh_output \
        -e API_URL="http://host.docker.internal:$PORT" \
        -e API_KEY="$api_key" \
        -v "$WORKDIR:/github/workspace" \
        "$IMAGE" . cyclonedx sbom.json >/tmp/upload.log 2>&1
    UPLOAD_RC=$?
    wait "$mock_pid" 2>/dev/null
    rm -rf "$WORKDIR"
}

if command -v python3 >/dev/null 2>&1; then
    echo "▶ Upload SBOM to API (success)"
    run_upload 200 "test-key-123"
    if [ "$UPLOAD_RC" -eq 0 ]; then
        pass "action succeeds when upload returns 2xx"
    else
        fail "action failed on successful upload (rc=$UPLOAD_RC)"; cat /tmp/upload.log
    fi
    if [ "$(jq -r '.bomFormat' "$BODY" 2>/dev/null)" = "CycloneDX" ]; then
        pass "API received the CycloneDX SBOM as the POST body"
    else
        fail "API did not receive the expected SBOM body"
    fi
    if head -n1 "$HDR" 2>/dev/null | grep -q "test-key-123"; then
        pass "API received the X-Api-Key header"
    else
        fail "API did not receive the X-Api-Key header"
    fi
    rm -f "$BODY" "$HDR"

    echo "▶ Upload failure (5xx) makes the action fail"
    run_upload 500 "test-key-123"
    if [ "$UPLOAD_RC" -ne 0 ] && [ "$UPLOAD_RC" -ne 99 ]; then
        pass "action exits non-zero when upload returns 5xx"
    else
        fail "action did not fail on 5xx upload (rc=$UPLOAD_RC)"; cat /tmp/upload.log
    fi
    rm -f "$BODY" "$HDR"
else
    echo "⏭  Skipping API upload tests (python3 not found)"
fi

# ---- Summary --------------------------------------------------------------
echo "=========================================="
echo " Results: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ]
