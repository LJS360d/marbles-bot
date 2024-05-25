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

discord_login_api=https://discord.com/api/v9/auth/login
RESPONSE=$(curl -s -X POST "$discord_login_api" \
  -H "Content-Type: application/json" \
  -d '{
    "login": "'"$DISCORD_LOGIN"'",
    "password": "'"$DISCORD_PASSWORD"'"
  }')

# ! DO NOT SHARE THIS TOKEN
TOKEN=$(echo $RESPONSE | grep -oP '(?<="token":")[^"]*')

if [ -n "$TOKEN" ]; then
  echo "Discord Login Success"
else
  echo "Discord Login Failed"
  exit 1
fi

echo "Application ID: $DISCORD_APPLICATION_ID"

proxy_config_api=https://discord.com/api/v9/applications/$DISCORD_APPLICATION_ID/proxy-config
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

curl -X POST -H "Content-Type: application/json" -H "Authorization: $TOKEN" -d "$payload" $proxy_config_api
