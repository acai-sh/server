# Dockerfile
#
# Template created with mix phx.gen.release
# Multi-stage build for devcontainer, release, and prod
#
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.3.1
ARG DEBIAN_VERSION=trixie-20260202-slim
# make sure to change the gh runner if you change this
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"



# ~~~~~~~~~~~~~~~~~~~~~~
#   🏗️ BUILDER STAGE
# ~~~~~~~~~~~~~~~~~~~~~~

FROM ${BUILDER_IMAGE} AS builder

# need git to import heroicons from github. If we migrate to the hex package or find a different alternative, we can remove this
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ~~~~~~~~~~~~~~~~~~~~~~
#    🛠️ DEV STAGE
# ~~~~~~~~~~~~~~~~~~~~~~

FROM builder AS dev
# non-root user to reference in docker-compose.yml and devcontainer.json
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user and install dev deps (no sudo at runtime)
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    openssh-client \
    inotify-tools \
    curl \
    postgresql-client-17 \
    && rm -rf /var/lib/apt/lists/*

# Configure homebrew as root, assign ownership to dev user
# You can only install as sudo, not as root, but my dev user doesn't have sudo.
RUN mkdir -p /home/linuxbrew/.linuxbrew \
    && chown -R $USERNAME:$USERNAME /home/linuxbrew/.linuxbrew

ENV LANG=C.UTF-8
ENV ELIXIR_ERL_OPTIONS="+fnu"

USER $USERNAME

# INSTALL HOMEBREW
# RUN NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# RUN brew install gh

# CONFIGURE PATH'
ENV PATH="/home/linuxbrew/.linuxbrew/bin:${PATH}"

# install opencode
RUN curl -fsSL https://opencode.ai/install | bash


# ~~~~~~~~~~~~~~~~~~~~~~
#    📦 RELEASE STAGE
# ~~~~~~~~~~~~~~~~~~~~~~

FROM builder AS release

# install hex + rebar
RUN mix local.hex --force \
    && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix assets.setup

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

COPY assets assets

# compile assets
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel
RUN mix release



# ~~~~~~~~~~~~~~~~~~~~~~
#    🚀 PROD STAGE
# ~~~~~~~~~~~~~~~~~~~~~~
FROM ${RUNNER_IMAGE} AS prod

RUN apt-get update \
    && apt-get install -y --no-install-recommends libstdc++6 openssl locales ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release. `acai` is set in mix.exs
COPY --from=release --chown=nobody:root /app/_build/${MIX_ENV}/rel/acai ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apt-get install`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
