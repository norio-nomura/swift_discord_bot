# syntax=docker/dockerfile:1
ARG DOCKER_IMAGE=swift:jammy
FROM ${DOCKER_IMAGE}
ARG USERNAME=bot
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,sharing=locked,target=/var/lib/apt \
    export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && \
    apt-get update -qq && apt-get install -qq \
    ca-certificates curl jq llvm unzip > /dev/null && \
    curl -fLsS https://deno.land/x/install/install.sh | DENO_INSTALL=/usr/local sh > /dev/null && \
    curl -fLsS https://github.com/cli/cli/releases/download/v2.5.0/gh_2.5.0_linux_amd64.tar.gz | tar zxf - --directory /usr --strip-components=1 && \
    curl -fLsS https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/bin/yq && chmod +x /usr/bin/yq  && \
    apt-get purge --auto-remove -qq curl > /dev/null && \
    mkdir -p /etc/skel/.cache/deno && \
    useradd -m $USERNAME

RUN deno --version
USER $USERNAME

# Install SwiftSDK
ARG SWIFT_SDK_DARWIN_URL SWIFT_SDK_DARWIN_CHECKSUM
RUN [ -z "${SWIFT_SDK_DARWIN_URL}" ] || swift sdk install ${SWIFT_SDK_DARWIN_URL} --checksum ${SWIFT_SDK_DARWIN_CHECKSUM} 
ARG SWIFT_SDK_WASM_URL SWIFT_SDK_WASM_CHECKSUM
RUN [ -z "${SWIFT_SDK_WASM_URL}" ] || swift sdk install ${SWIFT_SDK_WASM_URL} --checksum ${SWIFT_SDK_WASM_CHECKSUM} 

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
