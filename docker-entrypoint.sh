#!/bin/sh
set -e
db_path="${DATABASE_PATH:-/app/data/marbles_prod.db}"
db_dir="$(dirname "$db_path")"
mkdir -p "$db_dir"

# Migrate + seed here (same mount as the app). Railway preDeploy often has NO volume,
# so SQLite there is ephemeral — data never reached this container's DB file.
if [ "$(id -u)" = "0" ]; then
  chown -R nobody:nogroup "$db_dir" 2>/dev/null || true
  exec runuser -u nobody -- env RELEASE_NAME="$RELEASE_NAME" /bin/sh -c '
    set -e
    /app/bin/$RELEASE_NAME eval "Marbles.Release.migrate(); Marbles.Release.seed()"
    exec /app/bin/$RELEASE_NAME start "$@"
  ' sh "$@"
fi

/app/bin/${RELEASE_NAME} eval "Marbles.Release.migrate(); Marbles.Release.seed()"
exec "/app/bin/${RELEASE_NAME}" start "$@"
