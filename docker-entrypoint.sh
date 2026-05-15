#!/bin/sh
# Sub-Store 一体容器启动脚本
# 作用：
#   1. 用 envsubst 把 nginx 模板里的 ${BACKEND_PATH} 替换为 $SUB_STORE_FRONTEND_BACKEND_PATH
#   2. 并行启动 Sub-Store 后端 (node) 和 nginx
#   3. 任一进程退出则整体退出，便于 docker 重启策略接管

set -eu

BACKEND_PATH="${SUB_STORE_FRONTEND_BACKEND_PATH:-/api}"
export BACKEND_PATH

# 仅替换 ${BACKEND_PATH}，避免误伤 nginx 自带变量（如 $uri、$host）
envsubst '${BACKEND_PATH}' \
  < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/http.d/default.conf

echo "[entrypoint] BACKEND_PATH=${BACKEND_PATH}"
echo "[entrypoint] backend listen at ${SUB_STORE_BACKEND_API_HOST:-0.0.0.0}:${SUB_STORE_BACKEND_API_PORT:-3000}"
echo "[entrypoint] data dir: ${SUB_STORE_DATA_BASE_PATH:-/opt/app/data}"

# 信号转发：收到 TERM/INT 时通知子进程退出
term() {
  echo "[entrypoint] caught signal, stopping children..."
  [ -n "${BACKEND_PID:-}" ] && kill -TERM "$BACKEND_PID" 2>/dev/null || true
  [ -n "${NGINX_PID:-}" ] && kill -TERM "$NGINX_PID" 2>/dev/null || true
  wait
}
trap term INT TERM

# 启动 Sub-Store 后端
node /opt/app/sub-store.bundle.js &
BACKEND_PID=$!

# 启动 nginx（前台运行）
nginx -g 'daemon off;' &
NGINX_PID=$!

echo "[entrypoint] backend pid=${BACKEND_PID}, nginx pid=${NGINX_PID}"

# 任一进程退出，整体退出
wait -n
EXIT_CODE=$?
echo "[entrypoint] one of the processes exited with code ${EXIT_CODE}, shutting down..."
term
exit "${EXIT_CODE}"
