# syntax=docker/dockerfile:1.6
FROM alpine:3.20

ARG XRAY_VERSION=1.8.23

# 需要: envsubst, nc(healthcheck), curl/unzip
RUN apk add --no-cache ca-certificates tzdata bash curl unzip gettext busybox-extras \
 && mkdir -p /app/etc /app/assets /app/log

# 安装 Xray 二进制（amd64 示例；如需多架构可自行调整资产名）
RUN curl -fsSL -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/v${XRAY_VERSION}/Xray-linux-64.zip" \
 && unzip -q /tmp/xray.zip -d /tmp/xray \
 && install -m 0755 /tmp/xray/xray /usr/local/bin/xray \
 && rm -rf /tmp/xray /tmp/xray.zip

# 放入模板（你的仓库里要有同名文件）
COPY xray.json.template /app/etc/xray.json.template

# 内置 geosite/geoip 数据，供 geosite:/geoip: 规则使用
# 若你在 entrypoint 里 export XRAY_LOCATION_ASSET=/app/assets，xray 会从此处读取
RUN curl -fsSL -o /app/assets/geosite.dat \
      https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat \
 && curl -fsSL -o /app/assets/geoip.dat \
      https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat

# 入口脚本
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 非 root 运行
RUN adduser -D -H -s /sbin/nologin xray && chown -R xray:xray /app
USER xray

WORKDIR /app
# 不写 EXPOSE；你用 host 网络，不需要
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
