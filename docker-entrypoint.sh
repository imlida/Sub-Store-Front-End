#!/bin/sh
# Sub-Store 一体容器启动脚本
# 作用：
#   1. 规范化 SUB_STORE_FRONTEND_BACKEND_PATH（保证以 / 开头、不以 / 结尾）
#   2. 用 envsubst 把 nginx 模板里的 ${BACKEND_PATH} 替换为规范化后的值
#   3. 并行启动 Sub-Store 后端 (node) 和 nginx
#   4. 任一进程退出则整体退出，便于 docker 重启策略接管
#
# 注意：
#   - Sub-Store 后端提供 /api/...、/download/...、/share/... 固定路由
#   - 该变量仅作为 nginx 反代路径伪装：/<PATH>/<route>/xxx 被重写为 /<route>/xxx 后转发后端
#   - 留空（默认）：前端填 /api；设为 /Aa1Bb2：前端填 /Aa1Bb2/api

set -eu

# ---------- 1. 规范化 BACKEND_PATH ----------
RAW_PATH="${SUB_STORE_FRONTEND_BACKEND_PATH:-}"
BACKEND_PATH=""
if [ -n "$RAW_PATH" ]; then
  # 补前导斜杠
  case "$RAW_PATH" in
    /*) BACKEND_PATH="$RAW_PATH" ;;
     *) BACKEND_PATH="/$RAW_PATH" ;;
  esac
  # 去掉尾部斜杠，避免出现 //api/
  BACKEND_PATH="${BACKEND_PATH%/}"
fi
export BACKEND_PATH
# 把规范化后的值同步回 SUB_STORE_FRONTEND_BACKEND_PATH，确保后端读到的是同一份
export SUB_STORE_FRONTEND_BACKEND_PATH="$BACKEND_PATH"

# ---------- 2. 渲染 nginx 配置 ----------
# 仅替换 ${BACKEND_PATH}，避免误伤 nginx 自带变量（如 $uri、$host）
envsubst '${BACKEND_PATH}' \
  < /etc/nginx/templates/default.conf.template \
  > /etc/nginx/http.d/default.conf

echo "[entrypoint] ============================================="
echo "[entrypoint] SUB_STORE_FRONTEND_BACKEND_PATH = '${SUB_STORE_FRONTEND_BACKEND_PATH}'"
echo "[entrypoint] backend listen           = ${SUB_STORE_BACKEND_API_HOST:-0.0.0.0}:${SUB_STORE_BACKEND_API_PORT:-3000}"
echo "[entrypoint] backend internal routes  = /api/... /download/... /share/..."
echo "[entrypoint] nginx external routes   = ${BACKEND_PATH}/{api,download,share}/... -> backend fixed routes"
echo "[entrypoint] public share route      = /share/... -> /share/..."
echo "[entrypoint] data dir                 = ${SUB_STORE_DATA_BASE_PATH:-/opt/app/data}"
echo "[entrypoint] ============================================="
echo "[entrypoint] rendered nginx config (location blocks):"
grep -nE "^\s*location " /etc/nginx/http.d/default.conf || true
echo "[entrypoint] ============================================="

# ---------- 3. 校验 nginx 配置 ----------
nginx -t

# ---------- 4. 信号转发 ----------
term() {
  echo "[entrypoint] caught signal, stopping children..."
  [ -n "${BACKEND_PID:-}" ] && kill -TERM "$BACKEND_PID" 2>/dev/null || true
  [ -n "${NGINX_PID:-}" ]   && kill -TERM "$NGINX_PID"   2>/dev/null || true
  wait
}
trap term INT TERM

# ---------- 5. 启动后端 + nginx ----------
node /opt/app/sub-store.bundle.js &
BACKEND_PID=$!

nginx -g 'daemon off;' &
NGINX_PID=$!

echo "[entrypoint] backend pid=${BACKEND_PID}, nginx pid=${NGINX_PID}"

# 任一进程退出，整体退出
wait -n
EXIT_CODE=$?
echo "[entrypoint] one of the processes exited with code ${EXIT_CODE}, shutting down..."
term
exit "${EXIT_CODE}"
