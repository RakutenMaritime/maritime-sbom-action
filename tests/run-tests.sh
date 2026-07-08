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

# ---- Test: SPDX -----------------------------------------------------------
echo "▶ SPDX generation"
if run_action spdx sbom.spdx.json >/tmp/spdx.log 2>&1; then
    out="$WORKDIR/sbom.spdx.json"
    if [ -f "$out" ] \
        && [[ "$(jq -r '.spdxVersion' "$out")" == SPDX-* ]] \
        && [ "$(jq '.packages | length' "$out")" -ge 1 ]; then
        pass "spdx SBOM has spdxVersion and at least one package"
    else
        fail "spdx SBOM missing expected content"; cat /tmp/spdx.log
    fi
else
    fail "spdx run exited non-zero"; cat /tmp/spdx.log
fi
rm -rf "$WORKDIR"

# ---- Test: unsupported format fails --------------------------------------
echo "▶ Unsupported format is rejected"
if run_action bogus sbom.json >/tmp/bad.log 2>&1; then
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

# ---- Summary --------------------------------------------------------------
echo "=========================================="
echo " Results: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ]
