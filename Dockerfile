# Multi-stage build for RocketMQ Rust - Minimal runtime image
# Build stage
FROM rust:nightl as builder

# Install system dependencies for building
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    libcurl4-openssl-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install nightly Rust toolchain
RUN rustup default nightly && \
    rustup component add rustfmt clippy

# Set working directory
WORKDIR /app

# Copy all Cargo files first for better caching
COPY Cargo.toml Cargo.lock ./
COPY rocketmq-common/Cargo.toml ./rocketmq-common/Cargo.toml
COPY rocketmq-broker/Cargo.toml ./rocketmq-broker/Cargo.toml
COPY rocketmq-cli/Cargo.toml ./rocketmq-cli/Cargo.toml
COPY rocketmq-client/Cargo.toml ./rocketmq-client/Cargo.toml
COPY rocketmq-auth/Cargo.toml ./rocketmq-auth/Cargo.toml
COPY rocketmq-namesrv/Cargo.toml ./rocketmq-namesrv/Cargo.toml
COPY rocketmq-remoting/Cargo.toml ./rocketmq-remoting/Cargo.toml
COPY rocketmq-store/Cargo.toml ./rocketmq-store/Cargo.toml
COPY rocketmq-runtime/Cargo.toml ./rocketmq-runtime/Cargo.toml
COPY rocketmq-filter/Cargo.toml ./rocketmq-filter/Cargo.toml
COPY rocketmq-error/Cargo.toml ./rocketmq-error/Cargo.toml
COPY rocketmq-macros/Cargo.toml ./rocketmq-macros/Cargo.toml
COPY rocketmq-tools/Cargo.toml ./rocketmq-tools/Cargo.toml
COPY rocketmq-controller/Cargo.toml ./rocketmq-controller/Cargo.toml
COPY rocketmq-proxy/Cargo.toml ./rocketmq-proxy/Cargo.toml

# Copy all source code
COPY . .

# Build only the binaries we need (release mode)
RUN cargo build --release -p rocketmq-broker && \
    cargo build --release -p rocketmq-namesrv && \
    cargo build --release -p rocketmq-cli && \
    cargo build --release -p rocketmq-tools

# Runtime stage - Minimal Alpine image with only essential binaries
FROM alpine:3.19

# Install ca-certificates for HTTPS support
RUN apk add --no-cache ca-certificates

# Create non-root user
RUN addgroup -g 1000 rocketmq && \
    adduser -D -u 1000 -G rocketmq rocketmq

# Set working directory
WORKDIR /app

# Copy only the compiled binaries from builder stage
COPY --from=builder /app/target/release/rocketmq-broker-rust /usr/local/bin/
COPY --from=builder /app/target/release/rocketmq-namesrv-rust /usr/local/bin/
COPY --from=builder /app/target/release/rocketmq-cli-rust /usr/local/bin/
COPY --from=builder /app/target/release/rocketmq-admin-cli-rust /usr/local/bin/

# Copy configuration files
COPY --chown=rocketmq:rocketmq distribution/config/ /app/config/

# Create necessary directories
RUN mkdir -p /opt/data/rocketmq/store && \
    chown -R rocketmq:rocketmq /opt /app

# Change ownership
RUN chown -R rocketmq:rocketmq /app

# Switch to non-root user
USER rocketmq

# Expose ports for RocketMQ services
EXPOSE 9876 10911 10931

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD rocketmq-cli-rust --help > /dev/null 2>&1 || exit 1

# Default command starts the broker
CMD ["rocketmq-broker-rust", "--config", "/app/config/broker/broker.toml"]