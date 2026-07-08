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
    "parentCommit": {
      "commit": "0123456789abcdef",
      "date": "2026-07-08T16:50:00+09:00"
    },
    "tags": ["v1.2.3"],
    "generatedAt": "2026-07-08T08:11:45Z",
    "generator": "cdxgen"
  },
  "componentCount": 1,
  "components": [
    { "name": "lodash", "version": "4.17.21", "purl": "pkg:npm/lodash@4.17.21", "type": "library", "group": "" }
  ]
}
```

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

| Input | Description | Default |
|-------|-------------|---------|
| `sbom-file` | 업로드할 SBOM 파일 경로 | `sbom.json` |
| `api-url` | POST 대상 URL. 비어 있으면 업로드 스킵 | `''` |
| `api-key` | `X-Api-Key` 헤더로 전송할 API 키 | `''` |

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

