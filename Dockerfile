# syntax=docker/dockerfile:1.6

######## ① 构建阶段：拉源码并本机构架编译 ########
FROM golang:1.22-alpine AS build
# 用明确的版本分支/Tag，而不是 latest（可按需覆盖）
ARG XRAY_REF=v1.8.23
RUN apk add --no-cache git
WORKDIR /src

# 拉取 Xray 源码（指定分支/Tag/commit）
RUN git clone --depth=1 --branch ${XRAY_REF} https://github.com/XTLS/Xray-core.git .

# 官方推荐参数，一行编译；跟随当前构建机架构（不跨编译）
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -o /out/xray -trimpath -buildvcs=false -ldflags="-s -w -buildid=" -v ./main

######## ② 运行阶段：复制二进制并保持你原有布局 ########
FROM alpine:3.20

# 需要: envsubst, nc(healthcheck), curl(拉 geodata)
RUN apk add --no-cache ca-certificates tzdata bash curl gettext busybox-extras \
 && mkdir -p /app/etc /app/assets /app/log

# 从构建阶段复制编译好的 xray 可执行文件
COPY --from=build /out/xray /usr/local/bin/xray

# 放入模板
COPY xray-http.json.template /app/etc/xray-http.json.template
COPY xray-socks.json.template /app/etc/xray-socks.json.template

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
