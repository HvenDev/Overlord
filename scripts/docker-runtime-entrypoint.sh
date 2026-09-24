#!/bin/sh
set -eu

client_workspace=/app/Overlord-Client
client_seed=/opt/overlord-client-source

data_dir="${DATA_DIR:-/app/data}"
client_cache="${CLIENT_BUILD_CACHE:-/app/client-build-cache}"
go_tmp="${GOTMPDIR:-${client_cache}/go-tmp}"

# Ensure runtime-writable directories exist.
# Railway volumes are mounted after the image is built, so /app/data
# must be prepared at container startup rather than only at build time.
mkdir -p "$data_dir"
mkdir -p "$go_tmp"

# Verify that the database/data directory is writable before starting
# Overlord. This gives a clear startup error instead of a SQLite
# SQLITE_CANTOPEN error later.
if [ ! -w "$data_dir" ]; then
  echo "ERROR: Overlord data directory is not writable: $data_dir" >&2
  echo "The Railway volume mounted at $data_dir must be writable by the container user." >&2
  exit 1
fi

if [ ! -s "$client_workspace/go.mod" ]; then
  cp -a "$client_seed/." "$client_workspace/"
fi

exec "$@"

