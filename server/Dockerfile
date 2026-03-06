# ── Stage 1: Build ──────────────────────────────────────────────
FROM rust:1.87-bookworm AS builder

WORKDIR /build

# Cache dependencies first
COPY Cargo.toml Cargo.lock* ./
RUN mkdir src && echo "fn main(){}" > src/main.rs && \
    mkdir -p src/bin && echo "fn main(){}" > src/bin/opcua_sim.rs && \
    cargo build --release 2>/dev/null || true && \
    rm -rf src

# Build real source
COPY src/ src/
RUN cargo build --release --bin server

# ── Stage 2: Runtime ───────────────────────────────────────────
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /build/target/release/server /app/server
COPY config.toml /app/config.toml

# SQLite data directory
RUN mkdir -p /app/data

# Default port
EXPOSE 3000

ENV RUST_LOG=info

CMD ["/app/server"]
