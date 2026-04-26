#!/bin/sh
set -e
if [ -n "$DATABASE_PATH" ]; then
  db_path="$DATABASE_PATH"
elif [ -n "$RAILWAY_VOLUME_MOUNT_PATH" ]; then
  db_path="${RAILWAY_VOLUME_MOUNT_PATH%/}/prod.db"
else
  db_path="/app/data/prod.db"
fi
db_dir="$(dirname "$db_path")"
mkdir -p "$db_dir"

/app/bin/${RELEASE_NAME} eval "Marbles.Release.migrate(); Marbles.Release.seed()"
exec "/app/bin/${RELEASE_NAME}" start "$@"
