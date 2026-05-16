#!/bin/sh
set -eu

IMAGE="${IMAGE:-sub-store:local}"
DATA_DIR="${DATA_DIR:-$(pwd)/data}"
DEFAULT_CONTAINER="sub-store-route-default-test"
MAGIC_CONTAINER="sub-store-route-magic-test"

cleanup() {
  docker rm -f "$DEFAULT_CONTAINER" "$MAGIC_CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

request() {
  url="$1"
  output_file="$2"
  curl -fsS -o "$output_file" -w "%{http_code} %{content_type} %{size_download}" "$url"
}

assert_not_html() {
  label="$1"
  result="$2"
  content_type="$(printf '%s' "$result" | awk '{print $2}')"
  if printf '%s' "$content_type" | grep -qi 'text/html'; then
    echo "FAIL: $label returned HTML ($result)" >&2
    return 1
  fi
}

assert_contains() {
  label="$1"
  file="$2"
  pattern="$3"
  if ! grep -q "$pattern" "$file"; then
    echo "FAIL: $label did not contain expected pattern: $pattern" >&2
    return 1
  fi
}

cleanup

docker run -d --name "$DEFAULT_CONTAINER" -p 3102:80 \
  -e SUB_STORE_BACKEND_API_HOST=0.0.0.0 \
  -e SUB_STORE_BACKEND_API_PORT=3000 \
  -e SUB_STORE_DATA_BASE_PATH=/opt/app/data \
  -v "$DATA_DIR:/opt/app/data" \
  "$IMAGE" >/dev/null

docker run -d --name "$MAGIC_CONTAINER" -p 3103:80 \
  -e SUB_STORE_FRONTEND_BACKEND_PATH=/Aa1Bb2 \
  -e SUB_STORE_BACKEND_API_HOST=0.0.0.0 \
  -e SUB_STORE_BACKEND_API_PORT=3000 \
  -e SUB_STORE_DATA_BASE_PATH=/opt/app/data \
  -v "$DATA_DIR:/opt/app/data" \
  "$IMAGE" >/dev/null

sleep 2

default_api="$(request 'http://127.0.0.1:3102/api/utils/env' /tmp/sub-store-default-api.out)"
assert_not_html "default /api" "$default_api"
assert_contains "default /api" /tmp/sub-store-default-api.out '"status"'

default_download="$(request 'http://127.0.0.1:3102/download/equaldcdn?target=ClashMeta' /tmp/sub-store-default-download.out)"
assert_not_html "default /download" "$default_download"
assert_contains "default /download" /tmp/sub-store-default-download.out 'proxies:'

default_share="$(request 'http://127.0.0.1:3102/share/sub/equaldcdn?token=invalid' /tmp/sub-store-default-share.out)"
assert_not_html "default /share" "$default_share"

magic_api="$(request 'http://127.0.0.1:3103/Aa1Bb2/api/utils/env' /tmp/sub-store-magic-api.out)"
assert_not_html "magic /Aa1Bb2/api" "$magic_api"
assert_contains "magic /Aa1Bb2/api" /tmp/sub-store-magic-api.out '"status"'

magic_download="$(request 'http://127.0.0.1:3103/Aa1Bb2/download/equaldcdn?target=ClashMeta' /tmp/sub-store-magic-download.out)"
assert_not_html "magic /Aa1Bb2/download" "$magic_download"
assert_contains "magic /Aa1Bb2/download" /tmp/sub-store-magic-download.out 'proxies:'

magic_share_root="$(request 'http://127.0.0.1:3103/share/sub/equaldcdn?token=invalid' /tmp/sub-store-magic-share-root.out)"
assert_not_html "magic root /share" "$magic_share_root"

magic_share_prefixed="$(request 'http://127.0.0.1:3103/Aa1Bb2/share/sub/equaldcdn?token=invalid' /tmp/sub-store-magic-share-prefixed.out)"
assert_not_html "magic /Aa1Bb2/share" "$magic_share_prefixed"

echo "Docker route verification passed"
