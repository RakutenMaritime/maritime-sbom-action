# Rakuten SBOM Actions Release

## Generate and publish a versioned workflow

Running `.github/workflows/publish-sbom-workflow.yml` manually replaces both
`{{version}}` placeholders in `.github/templates/sbom-generation.yml.tpl` with
the supplied release tag. It writes the result to `sbom-generation.yml` and
uploads it to a fixed S3 object key. Each run updates that object to reference
the requested tag.

The workflow also creates an annotated Git tag on the commit from which the
workflow runs and pushes it to the remote repository. If the tag already points
to the same commit, it is reused. The workflow fails if the tag already points
to a different commit.

The `workflow_dispatch` form requires a release tag and a `dev` or `prod`
environment. Configure the following GitHub Actions secrets, Environment
variables, and Environment secrets before running it.

Set `DEV_S3_NAME` and `PROD_S3_NAME` as repository-level Actions secrets with
different bucket names. The workflow selects one of them according to the
chosen deployment environment and exports it as `S3_NAME`. The object key may
be identical because the buckets are separate:

```text
dev:  s3://company-sbom-workflows-dev/sbom-workflow/sbom.yml
prod: s3://company-sbom-workflows-prod/sbom-workflow/sbom.yml
```

| Scope | Type | Name | Example or purpose |
|-------|------|------|--------------------|
| Repository | Secret | `DEV_S3_NAME` | Development S3 bucket name |
| Repository | Secret | `PROD_S3_NAME` | Production S3 bucket name |
| `dev` | Variable | `AWS_REGION` | Development bucket's AWS Region |
| `dev` | Variable | `SBOM_WORKFLOW_S3_KEY` | Optional S3 object key |
| `dev` | Secret | `AWS_ROLE_ARN` | Development IAM role ARN |
| `prod` | Variable | `AWS_REGION` | Production bucket's AWS Region |
| `prod` | Variable | `SBOM_WORKFLOW_S3_KEY` | Optional S3 object key |
| `prod` | Secret | `AWS_ROLE_ARN` | Production IAM role ARN |

Selecting `dev` uses `secrets.DEV_S3_NAME`; selecting `prod` uses
`secrets.PROD_S3_NAME`. `AWS_REGION`, `SBOM_WORKFLOW_S3_KEY`, and `AWS_ROLE_ARN`
come from the selected GitHub Environment.

The default destination is:

```text
s3://$S3_NAME/sbom-workflow/sbom.yml
```

Set `SBOM_WORKFLOW_S3_KEY` to override the object key. The selected IAM role
requires `s3:PutObject` permission for that key and a trust policy that allows
GitHub OIDC authentication.

Because GitHub Actions does not allow dynamic expressions in `uses:`, the
publish workflow replaces both template placeholders with a literal tag such
as `v2.8`.

## Server-side signature verification example

```js
const crypto = require('crypto');

// rawBody is the original request body. Verify it before parsing.
const expected = 'sha256=' +
  crypto.createHmac('sha256', SIGNING_SECRET).update(rawBody).digest('hex');
const got = req.headers['x-signature-256'] || '';
const ok = got.length === expected.length &&
  crypto.timingSafeEqual(Buffer.from(got), Buffer.from(expected));
if (!ok) return res.status(401).send('invalid signature');
```

## Project structure

```text
.
├── generate/                    # SBOM generation action (Docker)
│   ├── action.yml
│   ├── Dockerfile               # Node.js, cdxgen, and jq
│   ├── generate-sbom            # Entry point
│   ├── scripts/
│   │   └── sbom-generator.sh    # cdxgen to plain JSON
│   └── tests/
│       └── run-tests.sh
└── upload/                      # SBOM upload action (composite)
    ├── action.yml
    ├── upload.sh                # curl POST
    └── tests/
        └── run-tests.sh
```

## Development

```bash
# Test the generate action (builds and runs its Docker image)
generate/tests/run-tests.sh

# Test the upload action on the host
upload/tests/run-tests.sh
```

## License

MIT
