# Rakuten SBOM Actions

GitHub Actions for generating a project's Software Bill of Materials (SBOM) and
sending it to an API. This repository provides two actions.

| Action | Path | Purpose |
|--------|------|---------|
| **generate** | `RakutenMaritime/maritime-sbom-action/generate` | Scan dependencies with `cdxgen` and produce a plain JSON SBOM |
| **upload** | `RakutenMaritime/maritime-sbom-action/upload` | Send a generated SBOM file to an API using `POST` |

### Generate and upload

```yaml
name: SBOM

on: [push, pull_request]

jobs:
  sbom:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate SBOM
        id: sbom
        uses: RakutenMaritime/maritime-sbom-action/generate@main
        with:
          scan-path: '.'           # Path to scan (default: .)
          output-file: 'sbom.json' # Output file (default: sbom.json)
          recurse: 'true'          # Recursively scan subdirectories

      - name: Display SBOM
        run: cat ${{ steps.sbom.outputs.sbom-file }}

      - name: Upload SBOM
        uses: RakutenMaritime/maritime-sbom-action/upload@main
        with:
          sbom-file: ${{ steps.sbom.outputs.sbom-file }}
          api-url: 'https://dev-ur-e27.rakuten-maritime.com/api/v1/sbom'
          api-key: ${{ secrets.SBOM_API_KEY }}   # Sent in the X-Api-Key header
```


## 🧩 generate action

Scans dependencies with `cdxgen` and produces a compact, plain JSON document like
the following.

```json
{
  "metadata": {
    "repository": "your-org/your-app",
    "repositoryUrl": "https://github.com/your-org/your-app",
    "ref": "refs/heads/main",
    "branch": "main",
    "commit": "abcdef1234567890",
    "commitMessage": "...",
    "commitAuthor": "Name <email>",
    "commitDate": "2026-07-08T17:08:30+09:00",
    "parentCommit": "0123456789abcdef",
    "parentCommitDate": "2026-07-08T16:50:00+09:00",
    "tags": ["v1.2.3"],
    "generatedAt": "2026-07-08T08:11:45Z",
    "generator": "cdxgen",
    "rootRef": "pkg:npm/your-app@1.0.0",
    "directDependencies": ["pkg:npm/a@1.0.0"]
  },
  "componentCount": 2,
  "components": [
    {
      "ref": "pkg:npm/a@1.0.0",
      "name": "a",
      "version": "1.0.0",
      "purl": "pkg:npm/a@1.0.0",
      "type": "library",
      "group": null,
      "licenses": ["MIT"],
      "hashes": [{ "alg": "SHA-512", "content": "…" }],
      "supplier": "...",
      "dependsOn": ["pkg:npm/b@2.0.0"]
    },
    {
      "ref": "pkg:npm/b@2.0.0",
      "name": "b",
      "version": "2.0.0",
      "purl": "pkg:npm/b@2.0.0",
      "type": "library",
      "group": null,
      "licenses": ["Apache-2.0"],
      "hashes": null,
      "supplier": null,
      "dependsOn": []
    }
  ]
}
```

Each component includes its identity (`name` and `type`), `version`, `licenses`
(an array of SPDX IDs, names, or expressions), integrity `hashes` (CycloneDX
`{ alg, content }` objects, such as SHA-512 values derived from a lockfile),
`supplier`, and direct dependencies. `dependsOn` contains the `ref` values of the
components on which the component directly depends. A `ref` is normally a purl.
Missing scalar values remain `null`, while missing lists remain `[]`.

> Because the scan also examines `.github/workflows`, `cdxgen` may identify CI
> GitHub Actions such as `actions/checkout` as `pkg:github/...` components. These
> are part of the build environment rather than project dependencies, so they
> are removed from both the component list and the dependency graph
> (`dependsOn` and `directDependencies`).

Transitive dependencies are represented by following each component's
`dependsOn` edges. For example, if direct dependency `a` has
`a.dependsOn = [b]`, the complete dependency set is `{a, b}`.
`metadata.rootRef` identifies the scanned project, while
`metadata.directDependencies` lists the top-level components on which the
project directly depends.

`metadata` describes the consumer repository being analyzed, not this action's
repository. It uses values such as `GITHUB_REPOSITORY` and `GITHUB_SHA`, falling
back to Git data from the scan path when necessary. This metadata is included in
the SBOM and sent to the API during upload. It can also include `parentCommit`
and tags attached to the current commit. Empty metadata fields are omitted.

> `parentCommit` requires Git history. The default `actions/checkout` depth is
> one commit, so use `fetch-depth: 0` in the consumer workflow when parent commit
> information is required.

| Input | Description | Default |
|-------|-------------|---------|
| `scan-path` | Path to scan | `.` |
| `output-file` | SBOM output path | `sbom.json` |
| `recurse` | Recursively scan subdirectories for monorepos; `false` scans only the top level | `false` |

| Output | Description |
|--------|-------------|
| `sbom-file` | Path to the generated SBOM file |

The generated components are printed to the log and shown as a table in the
GitHub Actions job summary.

## 📡 upload action

Sends the SBOM file to `api-url` using `POST` with
`Content-Type: application/json`. When `api-key` is set, it is sent in the
`X-Api-Key` header. A non-2xx response fails the action. An empty `api-url`
skips the upload.

When `signing-secret` is set, the request body is signed with HMAC-SHA256 and
the signature is sent as `X-Signature-256: sha256=<hex>`, following the GitHub
webhook convention. The server can recompute the HMAC with the shared secret to
detect payload modification or forgery.

| Input | Description | Default |
|-------|-------------|---------|
| `sbom-file` | SBOM file to upload | `sbom.json` |
| `api-url` | POST destination; an empty value skips the upload | `''` |
| `api-key` | API key sent in the `X-Api-Key` header | `''` |
| `signing-secret` | Shared secret for HMAC-SHA256 payload signing; sends `X-Signature-256` when set | `''` |


## 🔧 Development

```bash
# Test the generate action (builds and runs its Docker image)
generate/tests/run-tests.sh

# Test the upload action on the host
upload/tests/run-tests.sh
```

## 📝 License

MIT
