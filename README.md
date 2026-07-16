# Rakuten SBOM Actions

프로젝트의 Software Bill of Materials (SBOM)를 생성하고 API로 전송하는 GitHub
Action 모음입니다. 두 개의 액션으로 구성됩니다.

| Action | 경로 | 역할 |
|--------|------|------|
| **generate** | `RakutenMaritime/maritime-sbom-action/generate` | `cdxgen`으로 의존성을 스캔해 plain JSON SBOM 생성 |
| **upload** | `RakutenMaritime/maritime-sbom-action/upload` | 생성된 SBOM 파일을 API로 `POST` 전송 |

## 🚀 Usage

### 생성 + 전송 (조합)

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
          scan-path: '.'           # 스캔 경로 (default: .)
          output-file: 'sbom.json' # 출력 파일 경로 (default: sbom.json)

      - name: Display SBOM
        run: cat ${{ steps.sbom.outputs.sbom-file }}

      - name: Upload SBOM
        uses: RakutenMaritime/maritime-sbom-action/upload@main
        with:
          sbom-file: ${{ steps.sbom.outputs.sbom-file }}
          api-url: 'https://dev-ur-e27.rakuten-maritime.com/api/v1/sbom'
          api-key: ${{ secrets.SBOM_API_KEY }}   # X-Api-Key 헤더로 전송
```

### 생성만

```yaml
- uses: RakutenMaritime/maritime-sbom-action/generate@main
  id: sbom
- uses: actions/upload-artifact@v4
  with:
    name: sbom
    path: ${{ steps.sbom.outputs.sbom-file }}
```

## 🧩 generate action

`cdxgen`으로 의존성을 스캔한 뒤, 아래와 같은 **간결한 JSON 목록(plain)**으로
출력합니다.

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

각 컴포넌트는 **구성요소**(`name`/`type`), **버전**(`version`), **라이선스**
(`licenses`, SPDX id/name/expression 배열), **무결성 해시**(`hashes`, CycloneDX
`{ alg, content }` 배열 — 예: lockfile integrity에서 유도한 SHA-512), **공급자**
(`supplier`), 그리고 **직접 의존성**(`dependsOn`, 이 컴포넌트가 직접 의존하는 다른
컴포넌트의 `ref` 목록)을 포함합니다. `ref`는 `dependsOn`이 가리키는 식별자(주로
purl)입니다. 값이 없으면 `null`(목록은 `[]`)로 유지됩니다.

> 스캔은 `.github/workflows`도 훑기 때문에 cdxgen이 CI가 쓰는 **GitHub Actions**
> (`actions/checkout` 등, `pkg:github/…` purl)를 컴포넌트로 보고합니다. 이는 빌드
> 환경이지 프로젝트의 의존성이 아니므로, 컴포넌트 목록과 의존성 그래프
> (`dependsOn`/`directDependencies`) 양쪽에서 **제외**됩니다.

**전이(transitive) 의존성**은 각 컴포넌트의 `dependsOn`을 따라가며 만들어지는
전이 폐포(transitive closure)로 표현됩니다. 예: `directDependencies`의 `a`에서
`a.dependsOn = [b]`를 따라가면 프로젝트의 전체 의존성 `{a, b}`가 됩니다.
`metadata.rootRef`는 스캔 대상 프로젝트 자신을, `metadata.directDependencies`는
프로젝트가 **직접** 의존하는(최상위) 컴포넌트의 `ref` 목록을 가리킵니다.

`metadata`는 **이 액션을 실행하는 (분석 대상) 저장소**의 정보입니다. 액션 자신의
저장소가 아니라, 워크플로우가 돌아가는 소비자 repo의 `GITHUB_REPOSITORY`/`GITHUB_SHA`
등을 사용하며 (없으면 scan 경로의 git으로 폴백), 이 정보는 SBOM에 포함되어 **upload
시 API로 함께 전송**됩니다. `parentCommit`(직전 부모 커밋)과 `tags`(현재 커밋에
달린 태그)도 포함됩니다. 값이 없는 메타 필드는 출력에서 생략됩니다.

> `parentCommit`은 git 히스토리가 있어야 채워집니다. GitHub Actions 기본
> `actions/checkout`은 `fetch-depth: 1`(HEAD만)이므로, 부모 커밋 정보가 필요하면
> 소비자 워크플로우에서 `fetch-depth: 0`으로 체크아웃하세요.

| Input | Description | Default |
|-------|-------------|---------|
| `scan-path` | 스캔할 경로 | `.` |
| `output-file` | 출력 파일 경로 | `sbom.json` |

| Output | Description |
|--------|-------------|
| `sbom-file` | 생성된 SBOM 파일 경로 |

생성 결과는 로그에 목록으로 출력되며, GitHub Actions의 **Job Summary**에 컴포넌트
표로도 표시됩니다.

## 📡 upload action

`api-url`로 SBOM 파일을 `Content-Type: application/json`, `POST`로 전송합니다.
`api-key`가 있으면 `X-Api-Key` 헤더로 전송하며, 응답이 2xx가 아니면 실패합니다.
`api-url`이 비어 있으면 업로드를 건너뜁니다.

`signing-secret`을 지정하면 전송 본문을 HMAC-SHA256으로 서명해
`X-Signature-256: sha256=<hex>` 헤더로 함께 보냅니다 (GitHub 웹훅과 동일한 방식).
서버는 동일한 시크릿으로 수신 본문의 HMAC을 다시 계산해 일치 여부로 페이로드
위변조를 검증할 수 있습니다.

| Input | Description | Default |
|-------|-------------|---------|
| `sbom-file` | 업로드할 SBOM 파일 경로 | `sbom.json` |
| `api-url` | POST 대상 URL. 비어 있으면 업로드 스킵 | `''` |
| `api-key` | `X-Api-Key` 헤더로 전송할 API 키 | `''` |
| `signing-secret` | HMAC-SHA256 페이로드 서명용 공유 시크릿. 지정 시 `X-Signature-256` 헤더로 전송 | `''` |

서버 측 검증 예시 (Node.js):

```js
const crypto = require('crypto');

// rawBody: 수신한 원본 요청 바디(Buffer/string), 서명 검증은 파싱 전에 수행
const expected = 'sha256=' +
  crypto.createHmac('sha256', SIGNING_SECRET).update(rawBody).digest('hex');
const got = req.headers['x-signature-256'] || '';
const ok = got.length === expected.length &&
  crypto.timingSafeEqual(Buffer.from(got), Buffer.from(expected));
if (!ok) return res.status(401).send('invalid signature');
```

## 🏗️ 프로젝트 구조

```
.
├── generate/                    # SBOM 생성 액션 (Docker)
│   ├── action.yml
│   ├── Dockerfile               # node + cdxgen + jq
│   ├── generate-sbom            # 엔트리포인트
│   ├── scripts/
│   │   └── sbom-generator.sh    # cdxgen → plain JSON
│   └── tests/
│       └── run-tests.sh
└── upload/                      # SBOM 전송 액션 (composite)
    ├── action.yml
    ├── upload.sh                # curl POST
    └── tests/
        └── run-tests.sh
```

## 🔧 개발 방법

```bash
# 생성 액션 테스트 (Docker 이미지 빌드 후 실행)
generate/tests/run-tests.sh

# 전송 액션 테스트 (호스트에서 upload.sh 직접 구동)
upload/tests/run-tests.sh
```

## 📝 라이선스

MIT

