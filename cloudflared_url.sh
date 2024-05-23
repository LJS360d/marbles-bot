#!/bin/bash

container=marbles-cloudflared
output=$(docker logs $container 2>&1)

# Extract the URL from the output
url=$(echo "$output" | grep -o '.*\.trycloudflare.com')

if [ -n "$url" ]; then
  echo "Tunnel URL: $url"
else
  echo "Tunnel URL not found"
fi
# TODO
# application_id=1121903501941936128;
# https://discord.com/api/v9/applications/$application_id/proxy-config
# POST 
# url_map: [
#   {
#     prefix: "/",
#     target: $url
#   }
# ]