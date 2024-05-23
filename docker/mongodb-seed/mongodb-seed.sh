#!/bin/bash
set -e

mongoimport --host localhost --db marbles --collection marbles --type json --file /docker-entrypoint-initdb.d/marbles.seed.json --jsonArray
mongoimport --host localhost --db marbles --collection teams --type json --file /docker-entrypoint-initdb.d/teams.seed.json --jsonArray
