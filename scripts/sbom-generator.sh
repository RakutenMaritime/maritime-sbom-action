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

# Flatten the CycloneDX document into a plain JSON dependency list.
echo "🔄 Converting to a plain JSON dependency list..."
jq '{
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
