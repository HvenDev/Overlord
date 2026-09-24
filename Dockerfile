# syntax=docker/dockerfile:1

FROM oven/bun:1.4.0

WORKDIR /app

# System dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Install dependencies
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile

# Copy application
COPY . .

# Create data directory in the image
RUN mkdir -p /app/data \
    && chown -R bun:bun /app

ENV OVERLORD_DATA_DIR=/app/data

EXPOSE 8080

# IMPORTANT:
# Start as root so the mounted Railway volume can have its
# permissions fixed at container startup.
USER root

COPY overlord-entrypoint /usr/local/bin/overlord-entrypoint

RUN sed -i 's/\r$//' /usr/local/bin/overlord-entrypoint \
    && chmod +x /usr/local/bin/overlord-entrypoint

ENTRYPOINT ["/usr/local/bin/overlord-entrypoint"]
