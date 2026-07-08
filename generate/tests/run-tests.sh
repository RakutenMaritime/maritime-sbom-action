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
    : > "$WORKDIR/step_summary.md"
    docker run --rm --platform "$PLATFORM" \
        -e GITHUB_OUTPUT=/github/workspace/gh_output \
        -e GITHUB_STEP_SUMMARY=/github/workspace/step_summary.md \
        -e GITHUB_REPOSITORY=RakutenMaritime/maritime-sbom-action \
        -e GITHUB_SHA=abcdef1234567890abcdef1234567890abcdef12 \
        -e GITHUB_REF=refs/heads/main \
        -e GITHUB_REF_NAME=main \
        -e GITHUB_ACTION_REF=v1.6 \
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
    grep -q "pkg:npm/lodash@4.17.21" "$WORKDIR/step_summary.md" \
        && pass "writes component table to job summary" \
        || fail "did not write job summary"
    if [ "$(jq -r '.metadata.repository' "$out")" = "RakutenMaritime/maritime-sbom-action" ] \
        && [ "$(jq -r '.metadata.commit' "$out")" = "abcdef1234567890abcdef1234567890abcdef12" ] \
        && [ "$(jq -r '.metadata.repositoryUrl' "$out")" = "https://github.com/RakutenMaritime/maritime-sbom-action" ] \
        && [ "$(jq -r '.metadata.branch' "$out")" = "main" ] \
        && [ "$(jq -r '.metadata.actionVersion' "$out")" = "v1.6" ]; then
        pass "embeds source metadata (repository/commit/branch/actionVersion)"
    else
        fail "source metadata missing/incorrect"; jq '.metadata' "$out" 2>/dev/null
    fi
    # git-only fields are unavailable here (no git repo), so they must be omitted.
    if [ "$(jq '.metadata | has("commitMessage") or has("commitAuthor") or has("commitDate")' "$out")" = "false" ]; then
        pass "omits null metadata fields"
    else
        fail "null metadata fields were not omitted"; jq '.metadata' "$out" 2>/dev/null
    fi
else
    fail "generation run exited non-zero"; cat /tmp/gen.log
fi
rm -rf "$WORKDIR"

# ---- Test: tag captured from a tag-triggered ref (no git) ----------------
echo "▶ Tag captured from refs/tags ref"
WORKDIR="$(mktemp -d)"; cp -R "$FIXTURE/." "$WORKDIR/"
docker run --rm --platform "$PLATFORM" \
    -e GITHUB_REPOSITORY=your-org/your-app \
    -e GITHUB_SHA=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef \
    -e GITHUB_REF=refs/tags/v9.9.9 \
    -e GITHUB_REF_NAME=v9.9.9 \
    -v "$WORKDIR:/github/workspace" \
    "$IMAGE" . sbom.json >/tmp/tag.log 2>&1
out="$WORKDIR/sbom.json"
if [ "$(jq -r '.metadata.tags[0]' "$out" 2>/dev/null)" = "v9.9.9" ] \
    && [ "$(jq '.metadata | has("parentCommit")' "$out" 2>/dev/null)" = "false" ]; then
    pass "captures tag from ref; omits parentCommit without git history"
else
    fail "tag/parentCommit handling wrong"; jq '.metadata' "$out" 2>/dev/null; cat /tmp/tag.log
fi
rm -rf "$WORKDIR"

# ---- Test: parent commit + tag resolved from git -------------------------
if command -v git >/dev/null 2>&1; then
    echo "▶ Parent commit and tag from git history"
    GITDIR="$(mktemp -d)"
    cp -R "$FIXTURE/." "$GITDIR/"
    git -C "$GITDIR" init -q
    git -C "$GITDIR" -c user.email=t@example.com -c user.name=tester add -A
    git -C "$GITDIR" -c user.email=t@example.com -c user.name=tester commit -qm "first commit"
    : > "$GITDIR/CHANGELOG.md"
    git -C "$GITDIR" -c user.email=t@example.com -c user.name=tester add -A
    git -C "$GITDIR" -c user.email=t@example.com -c user.name=tester commit -qm "second commit"
    git -C "$GITDIR" tag v9.9.9
    docker run --rm --platform "$PLATFORM" \
        -v "$GITDIR:/github/workspace" \
        "$IMAGE" . sbom.json >/tmp/git.log 2>&1
    out="$GITDIR/sbom.json"
    parent_sha="$(git -C "$GITDIR" rev-parse HEAD~1)"
    if [ "$(jq -r '.metadata.parentCommit' "$out" 2>/dev/null)" = "$parent_sha" ] \
        && [ "$(jq -r '.metadata.parentCommitDate' "$out" 2>/dev/null)" != "null" ] \
        && [ "$(jq -r '.metadata.commitMessage' "$out" 2>/dev/null)" = "second commit" ] \
        && [ "$(jq -r '.metadata.tags[0]' "$out" 2>/dev/null)" = "v9.9.9" ]; then
        pass "resolves parentCommit (hash) + parentCommitDate and tag from git"
    else
        fail "git parentCommit/tag resolution wrong"; jq '.metadata' "$out" 2>/dev/null; cat /tmp/git.log
    fi
    rm -rf "$GITDIR"
else
    echo "⏭  Skipping git parentCommit test (git not found)"
fi

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
