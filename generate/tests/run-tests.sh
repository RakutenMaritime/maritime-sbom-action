#!/bin/bash
#
# Integration tests for the "generate" action.
#
# Builds the Docker image and drives it through its real entrypoint the same way
# GitHub Actions does, asserting on the generated plain-JSON SBOM.
#
# Usage:
#   generate/tests/run-tests.sh                 # build image, then run tests
#   IMAGE=my:tag SKIP_BUILD=1 generate/tests/run-tests.sh   # reuse an image

set -uo pipefail

ACTION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE="$ACTION_DIR/tests/fixtures/npm-project"
IMAGE="${IMAGE:-maritime-sbom-generate:test}"
PLATFORM="${PLATFORM:-linux/amd64}"

PASS=0
FAIL=0

pass() { echo "✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

require() {
    command -v "$1" >/dev/null 2>&1 || { echo "❌ Required tool not found: $1"; exit 2; }
}

require docker
require jq

# run_generate <output-file> [scan-path] -> leaves the SBOM in $WORKDIR.
WORKDIR=""
run_generate() {
    local output=$1 scan_path=${2:-.}
    WORKDIR="$(mktemp -d)"
    cp -R "$FIXTURE/." "$WORKDIR/"
    : > "$WORKDIR/gh_output"
    docker run --rm --platform "$PLATFORM" \
        -e GITHUB_OUTPUT=/github/workspace/gh_output \
        -v "$WORKDIR:/github/workspace" \
        "$IMAGE" "$scan_path" "$output"
}

echo "=========================================="
echo " generate action test suite"
echo "=========================================="

# ---- Build ----------------------------------------------------------------
if [ "${SKIP_BUILD:-}" = "1" ]; then
    echo "▶ Skipping build, using image: $IMAGE"
else
    echo "▶ Building image: $IMAGE"
    if docker build --platform "$PLATFORM" -t "$IMAGE" "$ACTION_DIR" >/dev/null 2>&1; then
        pass "docker image builds"
    else
        fail "docker image builds"; echo "Build failed; aborting."; exit 1
    fi
fi

# ---- Test: plain JSON generation ------------------------------------------
echo "▶ Plain JSON SBOM generation"
if run_generate sbom.json >/tmp/gen.log 2>&1; then
    out="$WORKDIR/sbom.json"
    if [ -f "$out" ] \
        && [ "$(jq '.componentCount' "$out")" -ge 1 ] \
        && [ "$(jq -r '.components[0].purl' "$out")" = "pkg:npm/lodash@4.17.21" ] \
        && [ "$(jq '[.components[] | select(.name=="lodash" and .version=="4.17.21")] | length' "$out")" -ge 1 ]; then
        pass "plain SBOM lists lodash with name/version/purl"
    else
        fail "plain SBOM missing expected content"; cat /tmp/gen.log; jq . "$out" 2>/dev/null
    fi
    grep -q "sbom-file=sbom.json" "$WORKDIR/gh_output" \
        && pass "sets sbom-file GitHub output" \
        || fail "did not set sbom-file output"
else
    fail "generation run exited non-zero"; cat /tmp/gen.log
fi
rm -rf "$WORKDIR"

# ---- Test: missing scan path fails ---------------------------------------
echo "▶ Missing scan path is rejected"
if run_generate sbom.json ./does-not-exist >/tmp/missing.log 2>&1; then
    fail "missing scan path should exit non-zero"
else
    grep -qi "does not exist" /tmp/missing.log \
        && pass "missing scan path exits non-zero with message" \
        || { fail "missing scan path wrong error"; cat /tmp/missing.log; }
fi
rm -rf "$WORKDIR"

# ---- Summary --------------------------------------------------------------
echo "=========================================="
echo " Results: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ]
