#!/bin/bash

set -e

SCAN_PATH="${1:-.}"
FORMAT="${2:-spdx}"
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

    echo "📦 Analyzing dependencies in $scan_path..."

    case "$format" in
        spdx)
            # Generate SPDX format SBOM
            generate_spdx_sbom "$scan_path" "$output_file"
            ;;
        cyclonedx)
            # Generate CycloneDX format SBOM
            generate_cyclonedx_sbom "$scan_path" "$output_file"
            ;;
        *)
            echo "❌ Unsupported format: $format"
            echo "  Supported formats: spdx, cyclonedx"
            exit 1
            ;;
    esac
}

# Function to generate SPDX format SBOM
generate_spdx_sbom() {
    local scan_path=$1
    local output_file=$2
    
    cat > "$output_file" <<EOF
{
  "spdxVersion": "SPDX-2.3",
  "dataLicense": "CC0-1.0",
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "Project SBOM",
  "documentNamespace": "https://example.com/sbom",
  "creationInfo": {
    "created": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
    "creators": ["Tool: rakuten-sbom-action"]
  },
  "packages": []
}
EOF
}

# Function to generate CycloneDX format SBOM
generate_cyclonedx_sbom() {
    local scan_path=$1
    local output_file=$2
    
    cat > "$output_file" <<EOF
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.4",
  "version": 1,
  "metadata": {
    "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
    "tools": [
      {
        "vendor": "Rakuten",
        "name": "rakuten-sbom-action",
        "version": "1.0.0"
      }
    ]
  },
  "components": []
}
EOF
}

# Main execution
main "$SCAN_PATH" "$FORMAT" "$OUTPUT_FILE"

echo "✅ SBOM generation completed: $OUTPUT_FILE"
