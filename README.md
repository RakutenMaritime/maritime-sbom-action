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
        uses: rakuten-symphony/sbom-action@v1
```

### 옵션 지정

```yaml
- name: Generate SBOM with Options
  uses: rakuten-symphony/sbom-action@v1
  with:
    format: 'cyclonedx'          # spdx or cyclonedx (default: spdx)
    scan-path: './src'           # 스캔 경로 (default: .)
    output-file: 'sbom.json'     # 출력 파일 경로 (default: sbom.json)
```

## 📋 Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `format` | SBOM 형식 (spdx, cyclonedx) | `spdx` | false |
| `output-file` | 출력 파일 경로 | `sbom.json` | false |
| `scan-path` | 스캔할 경로 | `.` | false |

## 📤 Outputs

| Output | Description |
|--------|-------------|
| `sbom-file` | 생성된 SBOM 파일 경로 |

### 출력값 사용 예시

```yaml
- name: Generate SBOM
  id: sbom
  uses: rakuten-symphony/sbom-action@v1

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

# 스크립트 실행
./generate-sbom ./test-dir spdx output.json
```

### Dockerfile 빌드

```bash
docker build -t rakuten-sbom-action:latest .
```

## 📝 라이선스

MIT

## 👥 기여

문제를 발견하거나 개선 사항이 있다면 이슈를 등록하거나 PR을 보내주세요.
