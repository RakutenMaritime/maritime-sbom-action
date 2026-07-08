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
        spdx)
            # cdxgen emits CycloneDX, then convert to SPDX
            generate_spdx_sbom "$scan_path" "$output_file"
            ;;
        *)
            echo "❌ Unsupported format: $format"
            echo "  Supported formats: cyclonedx, spdx"
            exit 1
            ;;
    esac
}

# Run cdxgen against a path and write a CycloneDX SBOM to the given file.
# --no-install-deps keeps the scan deterministic and offline: cdxgen relies on
# lockfiles / manifests instead of invoking package managers to install deps.
run_cdxgen() {
    local scan_path=$1
    local output_file=$2

    cdxgen \
        --no-install-deps \
        --recurse \
        --project-name "$(basename "$(cd "$scan_path" && pwd)")" \
        --output "$output_file" \
        "$scan_path"
}

# Generate a CycloneDX SBOM directly with cdxgen.
generate_cyclonedx_sbom() {
    local scan_path=$1
    local output_file=$2

    run_cdxgen "$scan_path" "$output_file"
}

# Generate an SPDX SBOM by producing CycloneDX with cdxgen and converting it
# with cyclonedx-cli.
generate_spdx_sbom() {
    local scan_path=$1
    local output_file=$2
    local cdx_tmp

    cdx_tmp="$(mktemp)"
    run_cdxgen "$scan_path" "$cdx_tmp"

    echo "🔄 Converting CycloneDX SBOM to SPDX..."
    cyclonedx convert \
        --input-file "$cdx_tmp" \
        --input-format json \
        --output-file "$output_file" \
        --output-format spdxjson

    rm -f "$cdx_tmp"
}

# Main execution
main "$SCAN_PATH" "$FORMAT" "$OUTPUT_FILE"

echo "✅ SBOM generation completed: $OUTPUT_FILE"
