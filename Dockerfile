# syntax=docker/dockerfile:1.7

FROM oven/bun:1.4.0

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git openssl unzip zip build-essential && rm -rf /var/lib/apt/lists/*

COPY Overlord-Server/package.json Overlord-Server/bun.lock* /app/Overlord-Server/

WORKDIR /app/Overlord-Server

RUN bun install --frozen-lockfile

WORKDIR /app

COPY Overlord-Server/ /app/Overlord-Server/
COPY Overlord-Client/ /app/Overlord-Client/
COPY scripts/ /app/scripts/

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV DATA_DIR=/app/data
ENV OVERLORD_ROOT=/app

WORKDIR /app/Overlord-Server

RUN bun run build

RUN bun run minify

RUN mkdir -p /app/data /app/Overlord-Server/dist

USER root

EXPOSE 8080

WORKDIR /app/Overlord-Server

CMD ["bun", "dist/index.js"]
