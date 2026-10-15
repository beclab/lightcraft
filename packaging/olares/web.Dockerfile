# syntax=docker/dockerfile:1
# Olares web image: the browser build (`cargo xtask web`, as in the `web` job of release.yml) behind nginx.
# Build from the repository root: docker build -f packaging/olares/web.Dockerfile .
ARG RUST_VERSION=1.99
ARG NGINX_VERSION=1.28-alpine

# The wasm output is architecture-independent, so multi-arch builds compile it once natively.
FROM --platform=$BUILDPLATFORM rust:${RUST_VERSION}-slim-bookworm AS builder
# Must match the wasm-bindgen version in Cargo.lock (cargo xtask web checks it).
ARG WASM_BINDGEN_VERSION=0.2.129
# Same pin as the craft-fonts checkout in release.yml.
ARG CRAFT_FONTS_REF=3d9ab3a132ed0eff457e424226a435a901da30d3
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && rustup target add wasm32-unknown-unknown
RUN set -eu; \
    case "$(uname -m)" in \
        x86_64) arch=x86_64 ;; \
        aarch64) arch=aarch64 ;; \
        *) echo 'The web builder supports amd64 and arm64' >&2; exit 1 ;; \
    esac; \
    name="wasm-bindgen-${WASM_BINDGEN_VERSION}-${arch}-unknown-linux-musl"; \
    url="https://github.com/wasm-bindgen/wasm-bindgen/releases/download/${WASM_BINDGEN_VERSION}"; \
    cd /tmp; \
    curl -fsSL --retry 3 "$url/$name.tar.gz" -o "$name.tar.gz"; \
    curl -fsSL --retry 3 "$url/$name.tar.gz.sha256sum" -o "$name.sha256"; \
    printf '%s  %s\n' "$(cut -d' ' -f1 "$name.sha256")" "$name.tar.gz" | sha256sum -c -; \
    tar -xzf "$name.tar.gz"; \
    install -m 0755 "$name/wasm-bindgen" /usr/local/bin/wasm-bindgen; \
    rm -rf "$name" "$name.tar.gz" "$name.sha256"; \
    wasm-bindgen --version; \
    mkdir -p /craft-fonts; \
    curl -fsSL --retry 3 "https://codeload.github.com/storytold/craft-fonts/tar.gz/${CRAFT_FONTS_REF}" \
        | tar -xzf - -C /craft-fonts --strip-components=1; \
    test -s /craft-fonts/fonts/manifest.txt

WORKDIR /src
COPY . .
ARG CARGO_BUILD_JOBS=4
ENV CRAFT_FONTS_DIR=/craft-fonts \
    CRAFT_FONTS_REQUIRED=1
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/target \
    cargo xtask web \
    && test -s target/web-site/index.html \
    && mkdir -p /site \
    && cp -R target/web-site/. /site/ \
    && rm -f /site/*.br

FROM nginx:${NGINX_VERSION} AS runtime
COPY packaging/olares/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /site/ /usr/share/nginx/html/
COPY LICENSE-MIT LICENSE-APACHE NOTICE assets/ATTRIBUTION.md /usr/share/nginx/html/
# Bypass the stock entrypoint: this configuration needs no runtime rewriting.
USER nginx
EXPOSE 8080
ENTRYPOINT []
CMD ["nginx", "-g", "daemon off;"]
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
