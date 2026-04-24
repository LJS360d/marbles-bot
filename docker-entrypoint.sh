#!/bin/sh
set -e
db_path="${DATABASE_PATH:-/app/data/marbles_prod.db}"
db_dir="$(dirname "$db_path")"
mkdir -p "$db_dir"
if [ "$(id -u)" = "0" ]; then
  chown -R nobody:nogroup "$db_dir" 2>/dev/null || true
  exec runuser -u nobody -- "/app/bin/${RELEASE_NAME}" start "$@"
fi
exec "/app/bin/${RELEASE_NAME}" start "$@"
