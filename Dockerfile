# syntax=docker/dockerfile:1
ARG DOCKER_IMAGE=swift:jammy

FROM ubuntu AS swift-sdks-downloader
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,sharing=locked,target=/var/lib/apt \
    export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && \
    apt-get update -qq && apt-get install -qq \
    curl > /dev/null

WORKDIR /swift-sdks
ARG SWIFT_SDKS
RUN [ -z "${SWIFT_SDKS}" ] || echo "${SWIFT_SDKS}" | while read -r sha256 url; do \
      curl -fLsS "${url}" -O -w "${sha256} %{filename_effective}\n"; \
    done | sha256sum --check --strict -
    
FROM ${DOCKER_IMAGE} AS final
ARG USERNAME=bot
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,sharing=locked,target=/var/lib/apt \
    set -x && \
    export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && \
    apt-get update -qq && apt-get install -qq \
    ca-certificates curl jq llvm unzip > /dev/null && \
    curl -fLsS https://deno.land/x/install/install.sh | DENO_INSTALL=/usr/local sh > /dev/null && \
    arch=$(dpkg --print-architecture) && \
    curl -fLsS https://github.com/cli/cli/releases/download/v2.67.0/gh_2.67.0_linux_${arch}.tar.gz | tar zxf - --directory /usr --strip-components=1 && \
    curl -fLsS "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch}" -o /usr/bin/yq && chmod +x /usr/bin/yq && \
    apt-get purge --auto-remove -qq curl > /dev/null && \
    mkdir -p /etc/skel/.cache/deno && \
    useradd -m $USERNAME

RUN deno --version
USER $USERNAME

# Install SwiftSDKs
RUN --mount=type=bind,from=swift-sdks-downloader,source=/swift-sdks,target=/swift-sdks \
    [ ! -f /swift-sdks/* ] || for sdk in /swift-sdks/*; do swift sdk install $sdk; done

COPY --chmod=755 swift-use-sdk.sh /usr/bin/

USER root
RUN <<'EOF'
#!/bin/bash
for target in $(swift-use-sdk.sh --list-targets); do
  ln -sf /usr/bin/swift-use-sdk.sh /usr/bin/swift-${target}
done
EOF
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
