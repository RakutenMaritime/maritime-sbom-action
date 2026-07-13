# Flatten a CycloneDX document (from cdxgen) into the plain-JSON SBOM this
# action emits. Source metadata is passed in via --arg (repository, commit,
# etc.). Run with: jq -f to-plain-sbom.jq --arg ... cyclonedx.json
#
# This transform is intentionally defensive: real cdxgen output can omit
# metadata.component, drop .dependencies, or carry unresolved (null-ref)
# dependency edges, none of which must crash the conversion.

def orNull: if . == "" then null else . end;

# ref -> [direct dependency refs], built from the CycloneDX dependency graph.
# Drop edges with a null/absent ref so from_entries never sees a null key
# (cdxgen can emit these for unresolved nodes in some scans).
(.dependencies // []
  | map(select(.ref != null) | { key: .ref, value: (.dependsOn // []) })
  | from_entries) as $deps
# Ref of the scanned project itself (the graph root). May be null when
# cdxgen omits metadata.component; indexing $deps with it is guarded below.
| (.metadata.component."bom-ref" // .metadata.component.purl) as $rootRef
| {
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
    generator: "cdxgen",
    actionVersion: ($actionVersion | orNull),
    # The scanned project itself and the refs it depends on directly, i.e.
    # the top-level dependencies. Every listed ref is a component below;
    # transitive dependencies are reached by following the dependsOn of
    # each component.
    rootRef: ($rootRef | orNull),
    directDependencies: (($deps[$rootRef]? // []) | if length == 0 then null else . end)
  } | with_entries(select(.value != null))),
  componentCount: ((.components // []) | length),
  components: [
    (.components // [])[] | (."bom-ref" // .purl) as $r | {
      # Stable identifier used to cross-reference dependsOn edges.
      ref: $r,
      name,
      version,
      purl,
      type,
      group: (.group | orNull),
      # License identifiers: SPDX id, else license name, else an SPDX
      # expression. Null when cdxgen could not determine any.
      licenses: (
        (.licenses // [])
        | map(.license.id // .license.name // .expression // empty)
        | if length == 0 then null else . end
      ),
      # Supplier/provider of the component, best-effort from CycloneDX
      # supplier -> publisher -> author.
      supplier: (.supplier.name // .publisher // .author | orNull),
      # Direct dependencies of this component (their refs). The full
      # transitive set is the closure of dependsOn across components.
      dependsOn: ($deps[$r]? // [])
    }
  ]
}
