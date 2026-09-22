FROM alpine:3

# Install dependencies (util-linux provides uuidgen)
RUN apk add --no-cache \
    bash \
    ca-certificates \
    curl \
    jq \
    rclone \
    rsync \
    util-linux

# Create non-root user with UID 1000
RUN adduser -D -u 1000 appuser

WORKDIR /opt/achterhus-server-tools

# Copy app contents (including entrypoint.sh and services/) to /app
COPY --chown=appuser:appuser lib/ ./lib/
COPY --chown=appuser:appuser app/ ./app/

# Ensure scripts are executable relative to WORKDIR /app
RUN chmod +x ./app/entrypoint.sh ./app/services/*.sh

# Define volume mount points
VOLUME ["/mnt/storage", "/mnt/mirror"]

USER appuser

ENTRYPOINT ["/opt/achterhus-server-tools/app/entrypoint.sh"]
CMD []
