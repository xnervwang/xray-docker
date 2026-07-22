# syntax=docker/dockerfile:1.6

######## ① Build stage: Pull source code and compile for current architecture ########
FROM golang:1.22-alpine AS build
# Use explicit version branch/tag instead of latest (can be overridden as needed)
ARG XRAY_REF=v1.8.23
RUN apk add --no-cache git
WORKDIR /src

# Pull Xray source code (specify branch/tag/commit)
RUN git clone --depth=1 --branch ${XRAY_REF} https://github.com/XTLS/Xray-core.git .

# Official recommended parameters, single-line compilation; follows current build architecture (no cross-compilation)
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -o /out/xray -trimpath -buildvcs=false -ldflags="-s -w -buildid=" -v ./main

######## ② Runtime stage: Copy binary and maintain your original layout ########
FROM alpine:3.20

# Requires: envsubst, nc(healthcheck), curl(pull geodata)
RUN apk add --no-cache ca-certificates tzdata bash curl gettext busybox-extras \
 && mkdir -p /app/etc /app/assets /app/log

# Copy compiled xray executable from build stage
COPY --from=build /out/xray /usr/local/bin/xray

# Place templates
COPY xray-http.json.template /app/etc/xray-http.json.template
COPY xray-socks.json.template /app/etc/xray-socks.json.template

# Built-in geosite/geoip data for geosite:/geoip: rules usage
# If you export XRAY_LOCATION_ASSET=/app/assets in entrypoint, xray will read from here
RUN curl -fsSL -o /app/assets/geosite.dat \
      https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat \
 && curl -fsSL -o /app/assets/geoip.dat \
      https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat

# Entry script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Run as non-root user
RUN adduser -D -H -s /sbin/nologin xray && chown -R xray:xray /app
USER xray

WORKDIR /app
# Don't write EXPOSE; you use host network, no need
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
