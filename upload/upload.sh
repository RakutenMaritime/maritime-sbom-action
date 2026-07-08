#!/bin/bash
#
# Upload an SBOM file to an API endpoint via HTTP POST.
#
# Environment:
#   SBOM_FILE  Path to the SBOM file to upload (default: sbom.json)
#   API_URL    Endpoint to POST to. Empty -> upload is skipped.
#   API_KEY    Optional; sent as the X-Api-Key header when present.

set -e

SBOM_FILE="${SBOM_FILE:-sbom.json}"

# Trim surrounding whitespace so a blank api-url reliably disables upload.
API_URL="${API_URL:-}"
API_URL="${API_URL#"${API_URL%%[![:space:]]*}"}"
API_URL="${API_URL%"${API_URL##*[![:space:]]}"}"

if [ -z "$API_URL" ]; then
    echo "ℹ️  api-url is empty; skipping API upload."
    exit 0
fi

if [ ! -f "$SBOM_FILE" ]; then
    echo "❌ SBOM file not found: $SBOM_FILE"
    exit 1
fi

echo "📡 Uploading $SBOM_FILE to $API_URL ..."

auth_args=()
if [ -n "${API_KEY:-}" ]; then
    auth_args=(-H "X-Api-Key: ${API_KEY}")
fi

response_body="$(mktemp)"
http_code="$(curl -sS -X POST \
    -H "Content-Type: application/json" \
    "${auth_args[@]}" \
    --data-binary "@${SBOM_FILE}" \
    -o "$response_body" \
    -w '%{http_code}' \
    "$API_URL")" || {
        echo "❌ SBOM upload failed (could not reach $API_URL)"
        rm -f "$response_body"
        exit 1
    }

if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    echo "✅ SBOM uploaded successfully (HTTP $http_code)"
else
    echo "❌ SBOM upload failed (HTTP $http_code)"
    cat "$response_body"
    rm -f "$response_body"
    exit 1
fi
rm -f "$response_body"
