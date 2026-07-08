FROM node:20-alpine

LABEL maintainer="Rakuten Symphony"

# Version pins
ARG CDXGEN_VERSION=11.4.3
ARG CYCLONEDX_CLI_VERSION=0.32.0

# cyclonedx-cli is a .NET app; run it without ICU to avoid globalization
# crashes on Alpine's musl runtime.
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# Install runtime dependencies, cdxgen (CycloneDX SBOM generator) and
# cyclonedx-cli (used to convert CycloneDX output to SPDX).
# .NET single-file cyclonedx-cli needs libstdc++/libgcc on Alpine.
RUN apk add --no-cache bash git curl libstdc++ libgcc \
    && npm install -g @cyclonedx/cdxgen@${CDXGEN_VERSION} \
    && ARCH="$(uname -m)" \
    && case "$ARCH" in \
         x86_64)  CLI_ASSET="cyclonedx-linux-musl-x64" ;; \
         aarch64) CLI_ASSET="cyclonedx-linux-arm64" && apk add --no-cache gcompat ;; \
         *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
       esac \
    && curl -sSfL "https://github.com/CycloneDX/cyclonedx-cli/releases/download/v${CYCLONEDX_CLI_VERSION}/${CLI_ASSET}" \
         -o /usr/local/bin/cyclonedx \
    && chmod +x /usr/local/bin/cyclonedx

# Copy scripts to container
COPY scripts/ /opt/sbom/scripts/
COPY generate-sbom /opt/sbom/

# Make scripts executable
RUN chmod +x /opt/sbom/generate-sbom /opt/sbom/scripts/*.sh

# Set working directory to workspace
WORKDIR /github/workspace

# Set entrypoint
ENTRYPOINT ["/opt/sbom/generate-sbom"]
