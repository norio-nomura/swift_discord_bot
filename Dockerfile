# syntax=docker/dockerfile:1
ARG DOCKER_IMAGE=ubuntu:18.04
FROM ${DOCKER_IMAGE}
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,sharing=locked,target=/var/lib/apt \
    export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && \
    apt-get -q update && apt-get -q install -y ca-certificates curl llvm unzip && \
    curl -fsSL https://deno.land/x/install/install.sh | DENO_INSTALL=/usr/local sh && \
    curl -L https://github.com/cli/cli/releases/download/v2.5.0/gh_2.5.0_linux_amd64.tar.gz | tar zxf - --directory /usr --strip-components=1 && \
    apt-get purge --auto-remove -y curl unzip && \
    useradd -m bot

# Install Bot
WORKDIR /bot

# Cache Dependencies
COPY deps.ts .
USER bot
RUN deno cache ./deps.ts

# Install remains
COPY bot.ts entrypoint.sh ./

# Start Bot
ENTRYPOINT [ "./entrypoint.sh" ]
