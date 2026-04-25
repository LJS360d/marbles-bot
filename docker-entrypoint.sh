#!/bin/sh
set -e
db_path="${DATABASE_PATH:-/app/data/marbles_prod.db}"
db_dir="$(dirname "$db_path")"
mkdir -p "$db_dir"

/app/bin/${RELEASE_NAME} eval "Marbles.Release.migrate(); Marbles.Release.seed()"
exec "/app/bin/${RELEASE_NAME}" start "$@"
