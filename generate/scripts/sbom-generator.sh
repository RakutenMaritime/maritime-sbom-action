#!/bin/bash

set -e

SCAN_PATH="${1:-.}"
OUTPUT_FILE="${2:-sbom.json}"

# Check if scan path exists
if [ ! -d "$SCAN_PATH" ]; then
    echo "❌ Scan path does not exist: $SCAN_PATH"
    exit 1
fi

echo "📦 Analyzing dependencies in $SCAN_PATH with cdxgen..."

# Generate a CycloneDX SBOM with cdxgen.
# --no-install-deps keeps the scan deterministic and offline: cdxgen relies on
# lockfiles / manifests instead of invoking package managers to install deps.
cdx_tmp="$(mktemp)"
cdxgen \
    --no-install-deps \
    --recurse \
    --project-name "$(basename "$(cd "$SCAN_PATH" && pwd)")" \
    --output "$cdx_tmp" \
    "$SCAN_PATH"

# Gather source metadata about the analyzed code. Prefer GitHub Actions
# environment variables, falling back to git in the scan path when available.
SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"
REPO="${GITHUB_REPOSITORY:-}"
COMMIT="${GITHUB_SHA:-}"
REF="${GITHUB_REF:-}"
BRANCH="${GITHUB_REF_NAME:-}"
COMMIT_MESSAGE=""
COMMIT_AUTHOR=""
COMMIT_DATE=""
PARENT_COMMIT=""
PARENT_DATE=""
TAGS=""

if command -v git >/dev/null 2>&1 && git -C "$SCAN_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Avoid "dubious ownership" errors on the mounted workspace.
    git config --global --add safe.directory '*' >/dev/null 2>&1 || true
    [ -z "$COMMIT" ] && COMMIT="$(git -C "$SCAN_PATH" rev-parse HEAD 2>/dev/null || true)"
    [ -z "$BRANCH" ] && BRANCH="$(git -C "$SCAN_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    COMMIT_MESSAGE="$(git -C "$SCAN_PATH" log -1 --pretty=%s 2>/dev/null || true)"
    COMMIT_AUTHOR="$(git -C "$SCAN_PATH" log -1 --pretty='%an <%ae>' 2>/dev/null || true)"
    COMMIT_DATE="$(git -C "$SCAN_PATH" log -1 --pretty=%cI 2>/dev/null || true)"
    if [ -z "$REPO" ]; then
        origin="$(git -C "$SCAN_PATH" config --get remote.origin.url 2>/dev/null || true)"
        # Normalize git@host:owner/repo.git or https://host/owner/repo.git -> owner/repo
        REPO="$(printf '%s' "$origin" | sed -E 's#(git@|https?://)[^/:]+[/:]##; s#\.git$##')"
    fi

    # Parent (previous) commit, when history is available (needs fetch-depth: 0).
    PARENT_COMMIT="$(git -C "$SCAN_PATH" rev-parse --verify -q HEAD~1 2>/dev/null || true)"
    if [ -n "$PARENT_COMMIT" ]; then
        PARENT_DATE="$(git -C "$SCAN_PATH" log -1 --pretty=%cI "$PARENT_COMMIT" 2>/dev/null || true)"
    fi

    # Tags pointing at the current commit (newline-separated).
    TAGS="$(git -C "$SCAN_PATH" tag --points-at HEAD 2>/dev/null || true)"
fi

# When triggered by a tag push, use the ref as the tag even without full git.
if [ -z "$TAGS" ] && [ "${GITHUB_REF:-}" != "${GITHUB_REF#refs/tags/}" ]; then
    TAGS="${GITHUB_REF_NAME:-${GITHUB_REF#refs/tags/}}"
fi

REPO_URL=""
[ -n "$REPO" ] && REPO_URL="${SERVER_URL%/}/$REPO"
GENERATED_AT="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

# Flatten the CycloneDX document into a plain JSON dependency list and attach
# the source metadata.
echo "🔄 Converting to a plain JSON dependency list..."
jq \
  --arg repository "$REPO" \
  --arg repositoryUrl "$REPO_URL" \
  --arg ref "$REF" \
  --arg branch "$BRANCH" \
  --arg commit "$COMMIT" \
  --arg commitMessage "$COMMIT_MESSAGE" \
  --arg commitAuthor "$COMMIT_AUTHOR" \
  --arg commitDate "$COMMIT_DATE" \
  --arg parentCommit "$PARENT_COMMIT" \
  --arg parentDate "$PARENT_DATE" \
  --arg tags "$TAGS" \
  --arg generatedAt "$GENERATED_AT" \
  '
  def orNull: if . == "" then null else . end;
  {
    metadata: ({
      repository: ($repository | orNull),
      repositoryUrl: ($repositoryUrl | orNull),
      ref: ($ref | orNull),
      branch: ($branch | orNull),
      commit: ($commit | orNull),
      commitMessage: ($commitMessage | orNull),
      commitAuthor: ($commitAuthor | orNull),
      commitDate: ($commitDate | orNull),
      parentCommit: ($parentCommit | orNull),
      parentCommitDate: ($parentDate | orNull),
      tags: (
        ($tags | split("\n") | map(select(length > 0)))
        | if length == 0 then null else . end
      ),
      generatedAt: $generatedAt,
      generator: "cdxgen"
    } | with_entries(select(.value != null))),
    componentCount: ((.components // []) | length),
    components: [
      (.components // [])[] | {
        name,
        version,
        purl,
        type,
        group: (.group // null)
      }
    ]
  }' "$cdx_tmp" > "$OUTPUT_FILE"

rm -f "$cdx_tmp"

echo "✅ SBOM generation completed: $OUTPUT_FILE"
