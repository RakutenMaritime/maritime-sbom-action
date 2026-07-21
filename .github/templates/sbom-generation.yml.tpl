name: SBOM · Generation

on:
  pull_request:

jobs:
  sbom:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v5

      - name: Generate SBOM
        id: sbom
        uses: RakutenMaritime/maritime-sbom-action/generate@{{version}}
        with:
          scan-path: ./samples/go
          output-file: sbom-go.json

      - name: Display SBOM
        run: cat "${{ steps.sbom.outputs.sbom-file }}"

      - name: Upload SBOM
        uses: RakutenMaritime/maritime-sbom-action/upload@{{version}}
        with:
          sbom-file: ${{ steps.sbom.outputs.sbom-file }}
          api-key: ${{ secrets.SBOM_API_KEY }} # X-Api-Key header
