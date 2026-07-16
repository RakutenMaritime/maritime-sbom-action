# Flatten a CycloneDX document (from cdxgen) into the plain-JSON SBOM this
# action emits. Source metadata is passed in via --arg (repository, commit,
# etc.). Run with: jq -f to-plain-sbom.jq --arg ... cyclonedx.json
#
# This transform is intentionally defensive: real cdxgen output can omit
# metadata.component, drop .dependencies, or carry unresolved (null-ref)
# dependency edges, none of which must crash the conversion.

def orNull: if . == "" then null else . end;

# The recursive scan also reads .github/workflows, so cdxgen reports the
# GitHub Actions the CI uses (pkg:github/...) as components — e.g.
# actions/checkout, and this action itself. Those describe the build
# environment, not the scanned project's dependencies, so they are dropped
# from the component list and from the dependency graph.
def isCiComponent: ((.purl // "") | startswith("pkg:github/"));

# Ref of the scanned project itself (the graph root). May be null when cdxgen
# omits metadata.component; every use below is guarded for that.
(.metadata.component."bom-ref" // .metadata.component.purl) as $rootRef
# cdxgen resolved no dependency graph at all: it named no root component AND
# emitted no dependency edges. Most ecosystems already report nothing in that
# situation — without a lockfile the npm and Python parsers return an empty
# component list, and Go still resolves a root from go.mod, so none of them
# reach this branch with real data. cdxgen's Cargo parser is the outlier: it
# falls back to Cargo.toml and lists the scanned crate ITSELF (plus unresolved
# manifest ranges), which is how a dependency-less crate ended up reported as
# its own dependency. Normalise that to what it is — no dependencies — without
# special-casing any ecosystem. Note this reads the document, not the
# filesystem: probing for lockfiles by name would wrongly blank a Go project
# that legitimately resolves from go.mod alone (no go.sum).
| ($rootRef == null and ((.dependencies // []) | length == 0)) as $unresolved
# Refs of the dropped CI components, as a set for membership lookup.
| ([ (.components // [])[] | select(isCiComponent) | (."bom-ref" // .purl) | select(. != null) ]
  | map({ key: ., value: true })
  | from_entries) as $ciRefs
# The scanned project's real dependencies: CI actions removed, and the scanned
# project itself removed — CycloneDX records the root in metadata.component, but
# cdxgen's Cargo parser also repeats it in components[], and a project is not
# its own dependency.
| (if $unresolved then []
   else (.components // [])
     | map(select((isCiComponent | not)
       and (($rootRef == null) or ((."bom-ref" // .purl) != $rootRef))))
   end) as $comps
# ref -> [direct dependency refs], built from the CycloneDX dependency graph.
# Drop edges with a null/absent ref so from_entries never sees a null key
# (cdxgen can emit these for unresolved nodes in some scans), and drop any
# dependsOn pointing at a removed CI component.
| (.dependencies // []
  | map(select(.ref != null)
    | { key: .ref,
        value: ((.dependsOn // []) | map(select(. != null)) | map(select($ciRefs[.] | not))) })
  | from_entries) as $deps
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
  componentCount: ($comps | length),
  components: [
    $comps[] | (."bom-ref" // .purl) as $r | {
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
      # Content hashes as CycloneDX { alg, content } pairs (e.g. SHA-512
      # derived from the lockfile integrity). Null when none are available.
      hashes: (
        (.hashes // [])
        | map(select(.content != null) | { alg: .alg, content: .content })
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
