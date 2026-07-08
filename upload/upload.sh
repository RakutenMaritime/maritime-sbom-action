#!/bin/bash
#
# Upload an SBOM file to an API endpoint via HTTP POST.
#
# Environment:
#   SBOM_FILE       Path to the SBOM file to upload (default: sbom.json)
#   API_URL         Endpoint to POST to. Empty -> upload is skipped.
#   API_KEY         Optional; sent as the X-Api-Key header when present.
#   SIGNING_SECRET  Optional; when set, the request body is signed with
#                   HMAC-SHA256 and sent as the X-Signature-256 header so the
#                   server can detect payload tampering / forgery.

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

# Sign the payload so the server can verify it was not tampered with in
# transit. We HMAC-SHA256 the exact bytes we POST (the SBOM file) with a shared
# secret and send the hex digest, matching the GitHub webhook convention:
#   X-Signature-256: sha256=<hex digest>
# The server recomputes the HMAC over the received body with the same secret
# and rejects the request if the digests differ.
sig_args=()
if [ -n "${SIGNING_SECRET:-}" ]; then
    if ! command -v openssl >/dev/null 2>&1; then
        echo "❌ SIGNING_SECRET is set but openssl is unavailable to sign the payload"
        exit 1
    fi
    signature="$(openssl dgst -sha256 -hmac "$SIGNING_SECRET" "$SBOM_FILE" | awk '{print $NF}')"
    if [ -z "$signature" ]; then
        echo "❌ Failed to compute the payload signature"
        exit 1
    fi
    sig_args=(-H "X-Signature-256: sha256=${signature}")
    echo "🔏 Signing payload with HMAC-SHA256 (X-Signature-256)"
fi

response_body="$(mktemp)"
http_code="$(curl -sS -X POST \
    -H "Content-Type: application/json" \
    "${auth_args[@]}" \
    "${sig_args[@]}" \
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
