# Sub-Store 前后端一体镜像
# - Stage 1：下载官方 Sub-Store 后端 bundle（不依赖第三方后端镜像）
# - Stage 2：以 node:lts-alpine 为基础，内置 nginx 同时托管前端静态资源与反向代理后端 API
# 容器内进程：nginx (80) + node sub-store.bundle.js (127.0.0.1:3000)
# 浏览器只需访问 80 端口即可，nginx 将 ${SUB_STORE_FRONTEND_BACKEND_PATH} 反向代理到本机后端

# ─────────────── Stage 1：下载后端 bundle ───────────────
FROM alpine:3.20 AS backend-fetcher

RUN apk add --no-cache wget ca-certificates

# 通过 build arg 切换后端版本，默认拉取最新发行版
# 自定义版本示例：docker build --build-arg SUB_STORE_BACKEND_VERSION=2.14.244 .
ARG SUB_STORE_BACKEND_VERSION=latest

WORKDIR /tmp
RUN set -eux; \
    if [ "$SUB_STORE_BACKEND_VERSION" = "latest" ]; then \
      url="https://github.com/sub-store-org/Sub-Store/releases/latest/download/sub-store.bundle.js"; \
    else \
      url="https://github.com/sub-store-org/Sub-Store/releases/download/${SUB_STORE_BACKEND_VERSION}/sub-store.bundle.js"; \
    fi; \
    echo "Downloading backend from: $url"; \
    wget -O sub-store.bundle.js "$url"

# ─────────────── Stage 2：运行时镜像 ───────────────
FROM node:lts-alpine

# nginx：托管前端 + 反向代理后端
# gettext：提供 envsubst，用于渲染 nginx 配置模板
# tini：作为 PID 1，转发信号、回收僵尸进程
RUN apk add --no-cache nginx gettext tini \
    && mkdir -p /run/nginx /opt/app/data /etc/nginx/templates

WORKDIR /opt/app

# 后端 bundle
COPY --from=backend-fetcher /tmp/sub-store.bundle.js /opt/app/sub-store.bundle.js

# 前端构建产物（CI 的 pnpm build 已生成）
COPY dist/ /usr/share/nginx/html/

# nginx 模板（包含 ${BACKEND_PATH} 占位符，启动时由 entrypoint 渲染）
COPY nginx.conf /etc/nginx/templates/default.conf.template

# 启动脚本：渲染 nginx 配置并并行拉起 nginx 与 node
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# 后端运行时默认环境变量（可在 docker-compose.yml / docker run -e 覆盖）
ENV SUB_STORE_BACKEND_API_HOST=0.0.0.0 \
    SUB_STORE_BACKEND_API_PORT=3000 \
    SUB_STORE_FRONTEND_BACKEND_PATH=/api \
    SUB_STORE_DATA_BASE_PATH=/opt/app/data

# 数据持久化目录
VOLUME ["/opt/app/data"]

# 仅暴露 80：nginx 同时承担静态资源与 API 反向代理
EXPOSE 80

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["docker-entrypoint.sh"]
