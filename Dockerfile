# syntax=docker/dockerfile:1
ARG SWIFT_PLATFORM=ubuntu
ARG PLATFORM_CODENAME=noble
ARG PLATFORM_IMAGE=${SWIFT_PLATFORM}:${PLATFORM_CODENAME}

ARG OS_MAJOR_VER=${PLATFORM_CODENAME}
ARG OS_MAJOR_VER=${OS_MAJOR_VER/focal/20}
ARG OS_MAJOR_VER=${OS_MAJOR_VER/jammy/22}
ARG OS_MAJOR_VER=${OS_MAJOR_VER/noble/24}
ARG OS_MIN_VER=${PLATFORM_CODENAME}
ARG OS_MIN_VER=${OS_MIN_VER/focal/04}
ARG OS_MIN_VER=${OS_MIN_VER/jammy/04}
ARG OS_MIN_VER=${OS_MIN_VER/noble/04}

ARG SWIFT_VERSION
ARG DOCKER_IMAGE=swift:${SWIFT_VERSION:+${SWIFT_VERSION}-}${PLATFORM_CODENAME}

ARG SWIFT_WEBROOT
ARG USE_SNAPSHOT=${SWIFT_WEBROOT:+true}
# select use-swift-snapshot-image-built-here or use-pre-built-swift-image
ARG SWIFT_IMAGE_SELECTOR=${USE_SNAPSHOT:+swift-snapshot-image-built-here}
ARG SWIFT_IMAGE_SELECTOR=${SWIFT_IMAGE_SELECTOR:-pre-built-swift-image}
ARG SWIFT_WEBROOT=https://download.swift.org/development

####################################################################################################
# swift-sdks-downloader
####################################################################################################
FROM ${PLATFORM_IMAGE} AS swift-sdks-downloader
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

# don't clean apt cache
RUN cd /etc/apt/apt.conf.d; rm -f docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > keep-cache

# install apt dependencies
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,sharing=locked,target=/var/lib/apt \
    apt-get update -qq && apt-get install -qq curl > /dev/null

# download Swift SDKs
WORKDIR /swift-sdks
ARG SWIFT_SDKS
RUN <<EOF
    [ -z "${SWIFT_SDKS:-}" ] || echo "${SWIFT_SDKS}" | while read -r sha256 url; do
      curl -fLsS "${url}" -O -w "${sha256} %{filename_effective}\n"
    done | sha256sum --check --strict -
EOF
####################################################################################################
# use-pre-built-swift-image
####################################################################################################
FROM ${DOCKER_IMAGE} AS use-pre-built-swift-image
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

# don't clean apt cache
RUN cd /etc/apt/apt.conf.d; rm -f docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > keep-cache

####################################################################################################
# use-swift-snapshot-image-built-here
####################################################################################################
# Based on https://github.com/swiftlang/swift-docker/blob/main/nightly-main/ubuntu/22.04/buildx/Dockerfile
FROM ${PLATFORM_IMAGE} AS use-swift-snapshot-image-built-here
# LABEL maintainer="Swift Infrastructure <swift-infrastructure@forums.swift.org>"
# LABEL description="Docker Container for the Swift programming language"
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

# don't clean apt cache
RUN cd /etc/apt/apt.conf.d; rm -f docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > keep-cache

# install apt dependencies
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,sharing=locked,target=/var/lib/apt \
    export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true && apt-get update -qq && \
    apt-get install -qq \
    binutils \
    git \
    unzip \
    gnupg2 \
    libc6-dev \
    libcurl4-openssl-dev \
    libedit2 \
    libgcc-13-dev \
    libpython3-dev \
    libsqlite3-0 \
    libstdc++-13-dev \
    libxml2-dev \
    libncurses-dev \
    libz3-dev \
    pkg-config \
    tzdata \
    zlib1g-dev \
    > /dev/null

ARG SWIFT_PLATFORM #=ubuntu
ARG OS_MAJOR_VER #=24
ARG OS_MIN_VER #=04
ARG SWIFT_WEBROOT #=https://download.swift.org/development

RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,sharing=locked,target=/var/lib/apt <<EOF
    case $(arch) in
    x86_64) OS_ARCH_SUFFIX='' ;;
    aarch64) OS_ARCH_SUFFIX='-aarch64' ;;
    *) echo >&2 "error: unsupported architecture: '$(arch)'"; exit 1 ;;
    esac;
    export OS_VER=$SWIFT_PLATFORM$OS_MAJOR_VER.$OS_MIN_VER$OS_ARCH_SUFFIX
    export PLATFORM_WEBROOT="$SWIFT_WEBROOT/$SWIFT_PLATFORM$OS_MAJOR_VER$OS_MIN_VER$OS_ARCH_SUFFIX"
    echo "${PLATFORM_WEBROOT}/latest-build.yml"
    # - Grab curl here so we cache better up above
    apt-get update -qq && apt-get install -qq curl > /dev/null
    # - Latest Toolchain info
    export $(curl -s ${PLATFORM_WEBROOT}/latest-build.yml | grep 'download:' | sed 's/:[^:\/\/]/=/g')
    export $(curl -s ${PLATFORM_WEBROOT}/latest-build.yml | grep 'download_signature:' | sed 's/:[^:\/\/]/=/g')
    export DOWNLOAD_DIR=$(echo $download | sed "s/-${OS_VER}.tar.gz//g")
    echo $DOWNLOAD_DIR > .swift_tag
    # - Download the GPG keys, Swift toolchain, and toolchain signature, and verify.
    export GNUPGHOME="$(mktemp -d)"
    curl -fLsS ${PLATFORM_WEBROOT}/${DOWNLOAD_DIR}/${download} -o latest_toolchain.tar.gz \
        ${PLATFORM_WEBROOT}/${DOWNLOAD_DIR}/${download_signature} -o latest_toolchain.tar.gz.sig
    curl -fLsS https://swift.org/keys/all-keys.asc | gpg --import --quiet - > /dev/null
    gpg --batch --quiet --verify latest_toolchain.tar.gz.sig latest_toolchain.tar.gz > /dev/null
    # - Unpack the toolchain, set libs permissions, and clean up.
    tar -xzf latest_toolchain.tar.gz --directory / --strip-components=1
    chmod -R o+r /usr/lib/swift
    rm -rf "$GNUPGHOME" latest_toolchain.tar.gz.sig latest_toolchain.tar.gz
    apt-get purge --auto-remove -qq curl > /dev/null

EOF

# Print Installed Swift Version
RUN swift --version && cat .swift_tag

RUN echo "[ -n \"\${TERM:-}\" -a -r /etc/motd ] && cat /etc/motd" >> /etc/bash.bashrc; \
    ( \
      printf "################################################################\n"; \
      printf "# %-60s #\n" ""; \
      printf "# %-60s #\n" "Swift Nightly Docker Image"; \
      printf "# %-60s #\n" "Tag: $(cat .swift_tag)"; \
      printf "# %-60s #\n" ""; \
      printf "################################################################\n" \
    ) > /etc/motd

####################################################################################################
# prepare-dependencies
####################################################################################################
FROM use-${SWIFT_IMAGE_SELECTOR} AS prepare-dependencies

# install apt dependencies
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,sharing=locked,target=/var/lib/apt \
    apt-get update -qq && apt-get install -qq ca-certificates curl file jq llvm unzip xz-utils > /dev/null

# install github-release-artifact-with-suffix script
COPY --chmod=755 <<'EOF' /usr/local/bin/github-release-artifact-with-suffix
#!/bin/bash -eu
api_url="https://api.github.com/repos/$1/releases/${3:+tags/}${3:-latest}"
download_url=$(curl -fsSL "${api_url}" -o - | jq -er '.assets|map(.browser_download_url|select(endswith("'$2'")))|first')
curl -fLsS "${download_url}" -o -
EOF

# install deno, gh, wasmtime, yq from GitHub releases
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,sharing=locked,target=/var/lib/apt <<EOF
    arch_arch=$(arch) # x86_64, aarch64
    dpkg_arch=$(dpkg --print-architecture) # amd64, arm64
    # install deno
    github-release-artifact-with-suffix "denoland/deno" "deno-${arch_arch}-unknown-linux-gnu.zip" v1.46.3 | funzip > /usr/local/bin/deno && chmod +x /usr/local/bin/deno
    deno --version
    # install gh
    github-release-artifact-with-suffix "cli/cli" "linux_${dpkg_arch}.tar.gz" | tar zxf - --directory /usr --strip-components=1
    gh --version
    # install wasmtime
    github-release-artifact-with-suffix "bytecodealliance/wasmtime" "${arch_arch}-linux.tar.xz" | tar xJf - --directory /usr/bin --strip-components=1 --wildcards "*/wasmtime"
    wasmtime --version
    # install yq
    curl -fLsS "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${dpkg_arch}" -o /usr/bin/yq && chmod +x /usr/bin/yq
    yq --version
EOF

# install swift-* wrapper scripts
COPY --chmod=755 swift-swiftc.sh /usr/bin/swift-swiftc
COPY --chmod=755 swift-testing.sh /usr/bin/swift-testing
COPY --chmod=755 swift-use-sdk.sh /usr/bin/swift-use-sdk

# create symbolic links to swift-use-sdk
RUN <<'EOF'
    for target in $(swift-use-sdk --list-targets); do
       ln -sf /usr/bin/swift-use-sdk /usr/bin/swift-${target}
    done
EOF

# setup user account for running bot
ARG USERNAME=bot
RUN mkdir -p /etc/skel/.cache/deno && useradd -m $USERNAME

# Install SwiftSDKs on the bot user
USER $USERNAME
RUN --mount=type=bind,from=swift-sdks-downloader,source=/swift-sdks,target=/swift-sdks \
    find /swift-sdks -type f | xargs -n 1 -r swift sdk install

####################################################################################################
# development stage for developing bot in devcontainer on VSCode
####################################################################################################
FROM prepare-dependencies AS debugger

ARG DEBUGGER_USERNAME=debugger
USER root

# Setup for debugging in VSCode
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,sharing=locked,target=/var/lib/apt <<EOF
    # Install git and sudo
    apt-get update -qq && apt-get install -qq git sudo > /dev/null

    # Create a user for debugging
    useradd -m $DEBUGGER_USERNAME
    echo $DEBUGGER_USERNAME ALL=\($USERNAME\) NOPASSWD:ALL > /etc/sudoers.d/$DEBUGGER_USERNAME
    chmod 0440 /etc/sudoers.d/$DEBUGGER_USERNAME

    # override scripts with symbolic links against the workspace
    for override in swiftc testing use-skd; do
        ln -sf /workspaces/swift_discord_bot/swift-${override}.sh /usr/bin/swift-${override}
    done
EOF

USER ${DEBUGGER_USERNAME}

####################################################################################################
# production stage for running bot on production
####################################################################################################
FROM prepare-dependencies AS production

# Install Bot Source Code
WORKDIR /bot

# Cache Dependencies
COPY deps.ts ./
RUN <<'EOF'
    DENO_ARGS=(--quiet)
    [[ "$(deno -v)" == "deno 1."* ]] || DENO_ARGS+=(
        --allow-import=deno.land:443,raw.githubusercontent.com:443,unpkg.com:443
    )
    deno cache "${DENO_ARGS[@]}" ./deps.ts
EOF

# Install remains
COPY bot.ts entrypoint.sh ./

# Start Bot
ENTRYPOINT [ "./entrypoint.sh" ]
