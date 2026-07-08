FROM python:3.12-alpine

LABEL maintainer="Rakuten Symphony"

# Install runtime dependencies and SBOM generation tools in a single layer
RUN apk add --no-cache bash git curl jq \
    && pip install --no-cache-dir cyclonedx-bom packageurl-python

# Copy scripts to container
COPY scripts/ /opt/sbom/scripts/
COPY generate-sbom /opt/sbom/

# Make scripts executable
RUN chmod +x /opt/sbom/generate-sbom /opt/sbom/scripts/*.sh

# Set working directory to workspace
WORKDIR /github/workspace

# Set entrypoint
ENTRYPOINT ["/opt/sbom/generate-sbom"]
