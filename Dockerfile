# syntax=docker/dockerfile:1.6
FROM alpine:3.20

ARG XRAY_VERSION=1.8.23

# 基础工具 + envsubst
RUN apk add --no-cache ca-certificates tzdata bash curl unzip grep sed coreutils gettext su-exec \
 && mkdir -p /app/bin /app/etc /app/log /app/run \
 && curl -fsSL -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" \
 && unzip -q /tmp/xray.zip -d /tmp/xray \
 && mv /tmp/xray/xray /app/bin/xray \
 && chmod +x /app/bin/xray \
 && rm -rf /tmp/xray /tmp/xray.zip

# 放入入口脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV XRAY_CONFIG_TEMPLATE=/app/etc/xray.json.template \
    XRAY_CONFIG=/app/etc/xray.json \
    XRAY_BIN=/app/bin/xray \
    XRAY_EXTRA_ARGS=""

# 以非 root 运行（可选）
RUN adduser -D -H -s /sbin/nologin xray && chown -R xray:xray /app
USER xray

WORKDIR /app
VOLUME ["/app/etc", "/app/log"]

EXPOSE 1080 1081 8080 8443 443

ENTRYPOINT ["/entrypoint.sh"]
CMD ["run"]
