# syntax=docker/dockerfile:1.7

FROM oven/bun:1.4.0

WORKDIR /app

# System packages required by Overlord and its build tooling

RUN apt-get update 
&& apt-get install -y --no-install-recommends 
ca-certificates 
curl 
git 
openssl 
unzip 
zip 
build-essential 
&& rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------

# Overlord Server dependencies

# ------------------------------------------------------------

COPY Overlord-Server/package.json Overlord-Server/bun.lock* /app/Overlord-Server/

WORKDIR /app/Overlord-Server

RUN bun install --frozen-lockfile

# ------------------------------------------------------------

# Copy the actual Overlord source tree

# ------------------------------------------------------------

WORKDIR /app

COPY Overlord-Server/ /app/Overlord-Server/
COPY Overlord-Client/ /app/Overlord-Client/

# Copy repository-level scripts used by Overlord

COPY scripts/ /app/scripts/

# Copy other project directories when they exist in the repository.

# These are intentionally NOT referenced as Docker COPY commands,

# because Docker fails if an optional directory does not exist.

# ------------------------------------------------------------

# Production environment

# ------------------------------------------------------------

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=5173

# This is the persistent Railway volume mount.

ENV DATA_DIR=/app/data

# Overlord uses this as its project root.

ENV OVERLORD_ROOT=/app

# ------------------------------------------------------------

# Build Overlord

# ------------------------------------------------------------

WORKDIR /app/Overlord-Server

# Build the actual project using the scripts defined in

# Overlord-Server/package.json.

#

# "build" runs:

# build:css

# build:web

# vendor

# build:bundle

#

# The bundle produces:

# dist/index.js

# dist/server/plugin-runtime/worker-host.js

RUN bun run build

# Production web assets

RUN bun run minify

# ------------------------------------------------------------

# Prepare persistent data directory

# ------------------------------------------------------------

RUN mkdir -p /app/data 
&& mkdir -p /app/Overlord-Server/dist

# ------------------------------------------------------------

# Railway volume permissions

# ------------------------------------------------------------

#

# Railway mounts the volume AFTER the image has been built.

# Therefore changing ownership here cannot change ownership

# of the mounted volume at runtime.

#

# We intentionally run the server as root so Overlord can create

# and write:

#

# /app/data/overlord.db

# /app/data/overlord.db-wal

# /app/data/overlord.db-shm

#

# on the Railway persistent volume.

USER root

# ------------------------------------------------------------

# Railway networking

# ------------------------------------------------------------

EXPOSE 5173

# ------------------------------------------------------------

# Start Overlord

# ------------------------------------------------------------

WORKDIR /app/Overlord-Server

CMD ["bun", "dist/index.js"]
