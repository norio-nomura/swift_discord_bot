# syntax=docker/dockerfile:1
ARG DOCKER_IMAGE=swift:jammy
FROM ${DOCKER_IMAGE}
ARG USERNAME=bot
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,sharing=locked,target=/var/lib/apt \
    export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && \
    apt-get update -qq && apt-get install -qq \
    ca-certificates curl llvm unzip > /dev/null && \
    curl -fLsS https://deno.land/x/install/install.sh | DENO_INSTALL=/usr/local sh > /dev/null && \
    curl -fLsS https://github.com/cli/cli/releases/download/v2.5.0/gh_2.5.0_linux_amd64.tar.gz | tar zxf - --directory /usr --strip-components=1 && \
    apt-get purge --auto-remove -qq curl unzip > /dev/null && \
    mkdir -p /etc/skel/.cache/deno && \
    useradd -m $USERNAME

RUN deno --version
USER $USERNAME

# Install Bot
WORKDIR /bot

# Cache Dependencies
COPY deps.ts ./
RUN deno cache --allow-import=deno.land:443,raw.githubusercontent.com:443,unpkg.com:443 --quiet ./deps.ts

# Install remains
COPY bot.ts entrypoint.sh ./

# Start Bot
ENTRYPOINT [ "./entrypoint.sh" ]
