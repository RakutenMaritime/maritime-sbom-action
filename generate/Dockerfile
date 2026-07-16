FROM node:22-alpine

LABEL maintainer="Rakuten Symphony"

# Version pins.
#
# 12.x is required for Maven: no JDK/maven is installed here (by design — the
# scan must see only the checked-out source, not a build environment), so
# cdxgen falls back to parsing pom.xml directly. That fallback reports nothing
# on 11.4.3; on 12.x it yields the declared dependencies.
ARG CDXGEN_VERSION=12.7.1

# Install runtime dependencies (jq flattens cdxgen's CycloneDX output to a
# plain JSON list) and cdxgen (SBOM generator).
RUN apk add --no-cache bash git jq \
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
