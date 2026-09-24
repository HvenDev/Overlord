#!/bin/sh
set -e

DATA_DIR="${OVERLORD_DATA_DIR:-/app/data}"

echo "[overlord] Preparing data directory: $DATA_DIR"

# The Railway volume is mounted AFTER the image is created,
# so permissions have to be fixed here at runtime.
mkdir -p "$DATA_DIR"

chown -R bun:bun "$DATA_DIR"
chmod 755 "$DATA_DIR"

# Verify that the actual Bun user can write to the mounted volume.
if ! su -s /bin/sh bun -c "touch '$DATA_DIR/.write-test'"; then
    echo "ERROR: Overlord data directory is not writable: $DATA_DIR"
    echo "The Railway volume mounted at $DATA_DIR must be writable by the container user."
    exit 1
fi

rm -f "$DATA_DIR/.write-test"

echo "[overlord] Data directory is writable: $DATA_DIR"

# Run Overlord as the normal Bun user.
exec su -s /bin/sh bun -c "cd /app && bun run /app/Overlord-Server/dist/index.js"
