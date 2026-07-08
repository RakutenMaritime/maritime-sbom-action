#!/bin/bash

set -e

SCAN_PATH="${1:-.}"
FORMAT="${2:-cyclonedx}"
OUTPUT_FILE="${3:-sbom.json}"

# Main execution logic
main() {
    local scan_path=$1
    local format=$2
    local output_file=$3

    # Check if scan path exists
    if [ ! -d "$scan_path" ]; then
        echo "❌ Scan path does not exist: $scan_path"
        exit 1
    fi

    echo "📦 Analyzing dependencies in $scan_path with cdxgen..."

    case "$format" in
        cyclonedx)
            # cdxgen natively emits CycloneDX
            generate_cyclonedx_sbom "$scan_path" "$output_file"
            ;;
        *)
            echo "❌ Unsupported format: $format"
            echo "  Supported formats: cyclonedx"
            exit 1
            ;;
    esac
}

# Generate a CycloneDX SBOM with cdxgen.
# --no-install-deps keeps the scan deterministic and offline: cdxgen relies on
# lockfiles / manifests instead of invoking package managers to install deps.
generate_cyclonedx_sbom() {
    local scan_path=$1
    local output_file=$2

    cdxgen \
        --no-install-deps \
        --recurse \
        --project-name "$(basename "$(cd "$scan_path" && pwd)")" \
        --output "$output_file" \
        "$scan_path"
}

# Main execution
main "$SCAN_PATH" "$FORMAT" "$OUTPUT_FILE"

echo "✅ SBOM generation completed: $OUTPUT_FILE"
