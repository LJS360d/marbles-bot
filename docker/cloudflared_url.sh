#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

source "$SCRIPT_DIR/.env"

container=$COMPOSE_PROJECT_NAME-cloudflared
url=$(docker logs $container 2>&1 | grep -o 'https://.*\.trycloudflare.com' | tail -n 1)

if [ -n "$url" ]; then
  echo $url
else
  echo "Tunnel URL not found"
  exit 1
fi

api=https://discord.com/api/v9/applications/$DISCORD_APPLICATION_ID/proxy-config
payload=$(cat <<EOF
{
  "url_map": [
    {
      "prefix": "/",
      "target": "$url"
    }
  ]
}
EOF
)

# TODO change discord auth / add auth refresh somehow
curl -X POST -H "Content-Type: application/json" -H "Authorization: $DISCORD_AUTH" -d "$payload" $api
