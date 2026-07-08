# Rakuten SBOM Action

주어진 프로젝트에 대한 Software Bill of Materials (SBOM)를 생성하는 GitHub Action입니다.

## 🚀 Usage

### 기본 사용법

```yaml
name: Generate SBOM

on: [push, pull_request]

jobs:
  sbom:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Generate SBOM
        uses: RakutenMaritime/maritime-sbom-action
```

### 옵션 지정

```yaml
- name: Generate SBOM with Options
  uses: RakutenMaritime/maritime-sbom-action
  with:
    scan-path: './src'           # 스캔 경로 (default: .)
    output-file: 'sbom.json'     # 출력 파일 경로 (default: sbom.json)
```

### 출력 형식

`cdxgen`으로 의존성을 스캔한 뒤, 아래와 같은 **간결한 JSON 목록(plain)**으로
출력합니다.

```json
{
  "componentCount": 1,
  "components": [
    { "name": "lodash", "version": "4.17.21", "purl": "pkg:npm/lodash@4.17.21", "type": "library", "group": "" }
  ]
}
```

### API로 SBOM 전송

`api-url`을 지정하면 생성된 SBOM(위 JSON)을 해당 URL로 `Content-Type: application/json`
으로 HTTP `POST` 전송합니다. `api-key`를 함께 지정하면 `X-Api-Key` 헤더로 전송됩니다.
응답이 2xx가 아니면 스텝이 실패합니다.

```yaml
- name: Generate & upload SBOM
  uses: RakutenMaritime/maritime-sbom-action
  with:
    api-url: 'https://dev-ur-e27.rakuten-maritime.com/api/v1/sbom'
    api-key: ${{ secrets.SBOM_API_KEY }}   # X-Api-Key 헤더로 전송
```

## 📋 Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `output-file` | 출력 파일 경로 | `sbom.json` | false |
| `scan-path` | 스캔할 경로 | `.` | false |
| `api-url` | 지정 시 생성된 SBOM을 이 URL로 POST 전송 | `https://dev-ur-e27.rakuten-maritime.com/api/v1/sbom` | false |
| `api-key` | 업로드 시 `X-Api-Key` 헤더로 전송할 API 키 | `''` | false |

## 📤 Outputs

| Output | Description |
|--------|-------------|
| `sbom-file` | 생성된 SBOM 파일 경로 |

### 출력값 사용 예시

```yaml
- name: Generate SBOM
  id: sbom
  uses: RakutenMaritime/maritime-sbom-action

- name: Upload SBOM
  uses: actions/upload-artifact@v3
  with:
    name: sbom
    path: ${{ steps.sbom.outputs.sbom-file }}
```

## 🏗️ 프로젝트 구조

```
.
├── Dockerfile           # Docker 컨테이너 이미지 정의
├── action.yml           # GitHub Action 메타데이터
├── generate-sbom        # 메인 엔트리포인트 스크립트
└── scripts/
    └── sbom-generator.sh    # SBOM 생성 로직
```

## 🔧 개발 방법

### 로컬 테스트

```bash
# 권한 설정
chmod +x generate-sbom scripts/sbom-generator.sh

# 스크립트 실행 (scan-path, output-file)
./generate-sbom ./test-dir output.json
```

### Dockerfile 빌드

```bash
docker build -t rakuten-sbom-action:latest .
```

## 📝 라이선스

MIT

## 👥 기여

문제를 발견하거나 개선 사항이 있다면 이슈를 등록하거나 PR을 보내주세요.
