# syntax=docker/dockerfile:1

FROM oven/bun:1.4.0

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        sqlite3 \
        util-linux \
    && rm -rf /var/lib/apt/lists/*

COPY package.json bun.lock* ./

RUN bun install --frozen-lockfile

COPY . .

ENV OVERLORD_DATA_DIR=/app/data

RUN mkdir -p /app/data \
    && chown -R bun:bun /app

EXPOSE 8080

USER root

CMD ["sh", "-c", "mkdir -p /app/data && chown -R bun:bun /app/data && chmod 755 /app/data && su -s /bin/sh bun -c 'cd /app && bun run /app/Overlord-Server/dist/index.js'"]
