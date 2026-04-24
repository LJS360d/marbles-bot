# Build stage: Elixir + Mix (hexpm tags: https://hub.docker.com/r/hexpm/elixir/tags — use -slim for smaller builds)
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.4
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-bookworm-20260421-slim"
ARG RUNNER_IMAGE="debian:bookworm-slim"

FROM ${BUILDER_IMAGE} AS builder
RUN apt-get update -y && apt-get install -y build-essential git curl \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
ENV MIX_ENV=prod
ARG RELEASE_NAME=marbles_umbrella
ENV RELEASE_NAME=${RELEASE_NAME}

COPY mix.exs mix.lock ./
COPY config config
COPY apps apps

RUN mix deps.get --only $MIX_ENV
RUN mix compile
RUN mix assets.deploy
RUN mix release ${RELEASE_NAME}

# Run stage
FROM ${RUNNER_IMAGE}
ARG RELEASE_NAME=marbles_umbrella
ENV RELEASE_NAME=${RELEASE_NAME}
RUN apt-get update -y && apt-get install -y libssl3 libncurses6 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app
RUN chown nobody:nogroup /app
USER nobody

COPY --from=builder --chown=nobody:nogroup /app/_build/prod/rel/${RELEASE_NAME} ./
ENV PHX_SERVER=true
ENV ECTO_EDITOR=

# Persisted data (SQLite DB, uploads, etc.)
# RUN mkdir -p /app/data
# VOLUME /app/data

EXPOSE 4000
CMD ["/bin/sh", "-c", "/app/bin/${RELEASE_NAME} start"]
