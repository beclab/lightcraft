# syntax=docker/dockerfile:1
# Olares agent image: lightcraft-cli's stdio MCP server behind supergateway (Streamable HTTP).
# Build from the repository root: docker build -f packaging/olares/agent.Dockerfile .
ARG RUST_VERSION=1.99
ARG NODE_VERSION=22-bookworm-slim

FROM rust:${RUST_VERSION}-slim-bookworm AS builder
WORKDIR /src
COPY . .
ARG CARGO_BUILD_JOBS=4
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/target \
    cargo build --release --locked -p lightcraft-cli \
    && install -m 0755 target/release/lightcraft-cli /usr/local/bin/lightcraft-cli

FROM node:${NODE_VERSION} AS runtime
ARG SUPERGATEWAY_VERSION=4.1.0
RUN npm install -g --omit=dev "supergateway@${SUPERGATEWAY_VERSION}" \
    && npm cache clean --force \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -o 1000 -g 1000 /data/files
COPY --from=builder /usr/local/bin/lightcraft-cli /usr/local/bin/lightcraft-cli
COPY LICENSE-MIT LICENSE-APACHE NOTICE assets/ATTRIBUTION.md /usr/share/doc/lightcraft/
# No --library: catalog.lock admits one process per library, and --stateful starts one per session.
ENV HOME=/tmp \
    LIGHTCRAFT_GPU=0 \
    MCP_PORT=8090
USER 1000:1000
WORKDIR /data/files
EXPOSE 8090
CMD ["sh", "-c", "exec supergateway --stdio \"lightcraft-cli mcp\" --outputTransport streamableHttp --stateful --sessionTimeout 1800000 --port $MCP_PORT --healthEndpoint /healthz"]
