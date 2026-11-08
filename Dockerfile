# syntax=docker/dockerfile:1
FROM golang:1.24-alpine AS build

# 版本号由 CI 用 --build-arg APP_VERSION=<tag> 注入（build-and-push.yml）；
# 本地直接 docker build 时回退到 dev，与 main.go 里 `var version = "dev"` 同口径。
ARG APP_VERSION=dev

WORKDIR /src
COPY go.mod ./
COPY . .
RUN CGO_ENABLED=0 go build -trimpath \
    -ldflags "-s -w -X main.version=${APP_VERSION}" \
    -o /out/deepaicode2api .

FROM alpine:3.20

# hadolint ignore=DL3018
RUN apk add --no-cache ca-certificates tzdata \
    && adduser -D -u 10001 app \
    && mkdir -p /data \
    && chown 10001:10001 /data

COPY --from=build /out/deepaicode2api /usr/local/bin/deepaicode2api

WORKDIR /app
USER 10001:10001

ENV DEEPAI2API_HOST=0.0.0.0 \
    DEEPAI2API_PORT=10087 \
    DEEPAI2API_DATA_PATH=/data/deepaicode2api-data.json

# 探活走 /healthz：该端点恒返回 200 JSON，只反映进程与路由是否活着，
# 不受上游账号池状态影响（池空也 200），因此适合做存活探针而非就绪探针。
# 用 alpine 自带的 busybox wget，不为 healthcheck 额外装 curl（保持镜像零额外依赖）。
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q --spider --timeout=4 "http://127.0.0.1:${DEEPAI2API_PORT}/healthz" || exit 1

VOLUME ["/data"]
EXPOSE 10087

ENTRYPOINT ["deepaicode2api"]
