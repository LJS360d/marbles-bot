# Build stage
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.4
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-bookworm-20260421-slim"
ARG RUNNER_IMAGE="debian:bookworm-slim"

FROM node:22-bookworm-slim AS asset_deps
WORKDIR /assets
COPY apps/marbles_web/assets/package.json apps/marbles_web/assets/package-lock.json ./
RUN npm ci

FROM ${BUILDER_IMAGE} AS builder
RUN apt-get update -y && apt-get install -y build-essential git curl \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV=prod
ARG RELEASE_NAME=marbles_umbrella
ENV RELEASE_NAME=${RELEASE_NAME}

# Copy only the mix manifests from each sub-app first
COPY mix.exs mix.lock ./
COPY config config
COPY apps/marbles/mix.exs apps/marbles/mix.exs
COPY apps/marbles_discordbot/mix.exs apps/marbles_discordbot/mix.exs
COPY apps/marbles_web/mix.exs apps/marbles_web/mix.exs

RUN mix deps.get --only $MIX_ENV

COPY apps apps
COPY --from=asset_deps /assets/node_modules /app/apps/marbles_web/assets/node_modules
RUN mix compile
RUN mix assets.deploy
RUN mix release ${RELEASE_NAME}
# Strip dev tools from ERTS and remove non-fingerprinted assets
RUN rel="/app/_build/prod/rel/${RELEASE_NAME}" \
  && rm -f "$rel"/erts-*/bin/dialyzer "$rel"/erts-*/bin/erlc "$rel"/erts-*/bin/ct_run "$rel"/erts-*/bin/typer \
  && find "$rel"/lib/marbles_web-*/priv/static \
    -regextype posix-extended \
    -type f \
    \( -name '*.js' -o -name '*.css' -o -name '*.svg' -o -name '*.txt' -o -name '*.ico' \) \
    ! -regex '.*-[a-f0-9]{32}\.(js|css|svg|txt|ico)$' \
    -delete \
  && find "$rel" -type f -name '*.map' -delete

# Run stage
FROM ${RUNNER_IMAGE}
ARG RELEASE_NAME=marbles_umbrella
ENV RELEASE_NAME=${RELEASE_NAME}
RUN apt-get update -y && apt-get install -y libssl3 libncurses6 ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

WORKDIR /app

COPY --from=builder --chown=nobody:nogroup /app/_build/prod/rel/${RELEASE_NAME} ./
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN mkdir -p /app/data \
  && chown -R nobody:nogroup /app \
  && chmod +x /usr/local/bin/docker-entrypoint.sh

ENV PHX_SERVER=true
ENV ECTO_EDITOR=

EXPOSE 4000
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["start"]
