#!/bin/bash
#
# Unit tests for the CycloneDX -> plain-JSON jq transform (to-plain-sbom.jq).
#
# These run the transform directly with jq (no Docker), so the conversion
# logic can be verified fast and deterministically, including the defensive
# handling of malformed / sparse cdxgen output.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="$SCRIPT_DIR/../scripts/to-plain-sbom.jq"

PASS=0
FAIL=0
pass() { echo "✅ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "❌ FAIL: $1"; FAIL=$((FAIL + 1)); }

command -v jq >/dev/null 2>&1 || { echo "❌ jq not found"; exit 2; }
[ -f "$FILTER" ] || { echo "❌ filter not found: $FILTER"; exit 2; }

# transform <cyclonedx-json> -> runs the filter with empty metadata args.
transform() {
    printf '%s' "$1" | jq \
        --arg repository "" --arg repositoryUrl "" --arg ref "" --arg branch "" \
        --arg commit "" --arg commitMessage "" --arg commitAuthor "" \
        --arg commitDate "" --arg parentCommit "" --arg parentDate "" \
        --arg tags "" --arg actionVersion "" --arg generatedAt "2026-01-01T00:00:00Z" \
        -f "$FILTER"
}

echo "=========================================="
echo " to-plain-sbom.jq unit tests"
echo "=========================================="

# ---- Does-not-crash cases (real, sparse cdxgen output shapes) -------------
# name|json — each must produce valid JSON without erroring.
run_nocrash() {
    local name=$1 json=$2
    if transform "$json" >/dev/null 2>/tmp/jq-err; then
        pass "no crash: $name"
    else
        fail "crashed: $name -> $(tail -1 /tmp/jq-err)"
    fi
}
run_nocrash "empty document"            '{}'
run_nocrash "no metadata.component"     '{"components":[{"name":"x","purl":"pkg:npm/x@1"}],"dependencies":[{"ref":"pkg:npm/x@1","dependsOn":[]}]}'
run_nocrash "null metadata"             '{"metadata":null,"components":[{"name":"x","purl":"pkg:npm/x@1"}]}'
run_nocrash "no dependencies field"     '{"metadata":{"component":{"purl":"pkg:npm/app@1"}},"components":[{"name":"x","purl":"pkg:npm/x@1"}]}'
run_nocrash "dependency with null ref"  '{"metadata":{"component":{"purl":"pkg:npm/app@1"}},"components":[{"name":"x","purl":"pkg:npm/x@1"}],"dependencies":[{"ref":null,"dependsOn":["pkg:npm/x@1"]}]}'
run_nocrash "dependency missing ref"    '{"components":[{"name":"x","purl":"pkg:npm/x@1"}],"dependencies":[{"dependsOn":["pkg:npm/x@1"]}]}'
run_nocrash "component without ref/purl" '{"components":[{"name":"x"}],"dependencies":[{"ref":"pkg:npm/x@1","dependsOn":[]}]}'

# ---- Correctness: a normal doc with a depth-2 transitive chain ------------
DOC='{
  "metadata": { "component": { "bom-ref": "pkg:npm/app@1.0.0", "purl": "pkg:npm/app@1.0.0" } },
  "components": [
    { "bom-ref": "pkg:npm/strip-ansi@6.0.1", "name": "strip-ansi", "version": "6.0.1", "purl": "pkg:npm/strip-ansi@6.0.1", "type": "library", "licenses": [{"license":{"id":"MIT"}}], "publisher": "Sindre", "hashes": [{"alg":"SHA-512","content":"abc123"}] },
    { "bom-ref": "pkg:npm/ansi-regex@5.0.1", "name": "ansi-regex", "version": "5.0.1", "purl": "pkg:npm/ansi-regex@5.0.1", "type": "library", "licenses": [{"license":{"name":"MIT License"}}] }
  ],
  "dependencies": [
    { "ref": "pkg:npm/app@1.0.0", "dependsOn": ["pkg:npm/strip-ansi@6.0.1"] },
    { "ref": "pkg:npm/strip-ansi@6.0.1", "dependsOn": ["pkg:npm/ansi-regex@5.0.1"] },
    { "ref": "pkg:npm/ansi-regex@5.0.1", "dependsOn": [] }
  ]
}'
OUT="$(transform "$DOC")"

check() { # <name> <jq-expr> <expected>
    local got; got="$(printf '%s' "$OUT" | jq -c "$2" 2>/dev/null)"
    if [ "$got" = "$3" ]; then pass "$1"; else fail "$1 (got $got, want $3)"; fi
}
check "componentCount"                 '.componentCount' '2'
check "rootRef"                        '.metadata.rootRef' '"pkg:npm/app@1.0.0"'
check "directDependencies"             '.metadata.directDependencies' '["pkg:npm/strip-ansi@6.0.1"]'
check "license via SPDX id"            '.components[]|select(.name=="strip-ansi").licenses' '["MIT"]'
check "license via name"               '.components[]|select(.name=="ansi-regex").licenses' '["MIT License"]'
check "supplier via publisher"         '.components[]|select(.name=="strip-ansi").supplier' '"Sindre"'
check "hashes preserved (alg/content)"  '.components[]|select(.name=="strip-ansi").hashes' '[{"alg":"SHA-512","content":"abc123"}]'
check "hashes null when absent"         '.components[]|select(.name=="ansi-regex").hashes' 'null'
check "transitive dependsOn edge"      '.components[]|select(.name=="strip-ansi").dependsOn' '["pkg:npm/ansi-regex@5.0.1"]'
check "leaf dependsOn is []"           '.components[]|select(.name=="ansi-regex").dependsOn' '[]'
check "no top-level dependencies key"  'has("dependencies")' 'false'

# ---- GitHub Actions (CI environment) are excluded ------------------------
# cdxgen's recursive scan reads .github/workflows and reports the actions the
# CI uses as pkg:github/... components. Those must not appear in the SBOM.
CI_DOC='{
  "metadata": { "component": { "bom-ref": "pkg:cargo/app@1.0.0", "purl": "pkg:cargo/app@1.0.0" } },
  "components": [
    { "bom-ref": "pkg:github/actions/checkout@v5", "name": "checkout", "version": "v5", "purl": "pkg:github/actions/checkout@v5", "type": "application" },
    { "bom-ref": "pkg:github/RakutenMaritime%2Fmaritime-sbom-action%2Fgenerate@v2.2", "name": "generate", "version": "v2.2", "purl": "pkg:github/RakutenMaritime%2Fmaritime-sbom-action%2Fgenerate@v2.2", "type": "application" },
    { "bom-ref": "pkg:cargo/spi@0.1.0", "name": "spi", "version": "0.1.0", "purl": "pkg:cargo/spi@0.1.0", "type": "library" }
  ],
  "dependencies": [
    { "ref": "pkg:cargo/app@1.0.0", "dependsOn": ["pkg:cargo/spi@0.1.0", "pkg:github/actions/checkout@v5"] },
    { "ref": "pkg:cargo/spi@0.1.0", "dependsOn": ["pkg:github/actions/checkout@v5"] },
    { "ref": "pkg:github/actions/checkout@v5", "dependsOn": [] }
  ]
}'
CI_OUT="$(transform "$CI_DOC")"
ci_check() { # <name> <jq-expr> <expected>
    local got; got="$(printf '%s' "$CI_OUT" | jq -c "$2" 2>/dev/null)"
    if [ "$got" = "$3" ]; then pass "$1"; else fail "$1 (got $got, want $3)"; fi
}
ci_check "drops pkg:github components"        '[.components[]|select(.purl|startswith("pkg:github/"))]|length' '0'
ci_check "keeps real (cargo) component"       '[.components[]|.name]' '["spi"]'
ci_check "componentCount excludes CI actions" '.componentCount' '1'
ci_check "directDependencies excludes CI"     '.metadata.directDependencies' '["pkg:cargo/spi@0.1.0"]'
ci_check "dependsOn drops CI refs"            '.components[]|select(.name=="spi").dependsOn' '[]'

echo "=========================================="
echo " Results: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ]
