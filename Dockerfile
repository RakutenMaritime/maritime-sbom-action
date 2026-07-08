FROM node:20-alpine

LABEL maintainer="Rakuten Symphony"

# Version pins
ARG CDXGEN_VERSION=11.4.3

# Install runtime dependencies and cdxgen (CycloneDX SBOM generator).
RUN apk add --no-cache bash git \
    && npm install -g @cyclonedx/cdxgen@${CDXGEN_VERSION}

# Copy scripts to container
COPY scripts/ /opt/sbom/scripts/
COPY generate-sbom /opt/sbom/

# Make scripts executable
RUN chmod +x /opt/sbom/generate-sbom /opt/sbom/scripts/*.sh

# Set working directory to workspace
WORKDIR /github/workspace

# Set entrypoint
ENTRYPOINT ["/opt/sbom/generate-sbom"]
