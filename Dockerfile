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
ARG SWIFT_WEBROOT=https://download.swift.org/development

# build arg to control whether to use a pre-built image or build the snapshot image here
ARG USE_SNAPSHOT
# If empty, treat as false
ARG _PARSE_USE_SNAPSHOT=${USE_SNAPSHOT:-false}
# remove truthy values
ARG _PARSE_USE_SNAPSHOT=${_PARSE_USE_SNAPSHOT#ON}
ARG _PARSE_USE_SNAPSHOT=${_PARSE_USE_SNAPSHOT#on}
ARG _PARSE_USE_SNAPSHOT=${_PARSE_USE_SNAPSHOT#TRUE}
ARG _PARSE_USE_SNAPSHOT=${_PARSE_USE_SNAPSHOT#true}
ARG _PARSE_USE_SNAPSHOT=${_PARSE_USE_SNAPSHOT#YES}
ARG _PARSE_USE_SNAPSHOT=${_PARSE_USE_SNAPSHOT#yes}
ARG _PARSE_USE_SNAPSHOT=${_PARSE_USE_SNAPSHOT#1}
# if not empty, USE_SNAPSHOT is false, use pre-built image
ARG SWIFT_IMAGE_SELECTOR=${_PARSE_USE_SNAPSHOT:+pre-built-swift-image}
# if empty, USE_SNAPSHOT is true, build snapshot image
ARG SWIFT_IMAGE_SELECTOR=${SWIFT_IMAGE_SELECTOR:-swift-snapshot-image-built-here}

# build arg to control whether to use swift sdks or not
ARG USE_SWIFT_SDKS
ARG _PARSE_USE_SWIFT_SDKS=${USE_SWIFT_SDKS:-false}
# remove truthy values
ARG _PARSE_USE_SWIFT_SDKS=${_PARSE_USE_SWIFT_SDKS#ON}
ARG _PARSE_USE_SWIFT_SDKS=${_PARSE_USE_SWIFT_SDKS#on}
ARG _PARSE_USE_SWIFT_SDKS=${_PARSE_USE_SWIFT_SDKS#TRUE}
ARG _PARSE_USE_SWIFT_SDKS=${_PARSE_USE_SWIFT_SDKS#true}
ARG _PARSE_USE_SWIFT_SDKS=${_PARSE_USE_SWIFT_SDKS#YES}
ARG _PARSE_USE_SWIFT_SDKS=${_PARSE_USE_SWIFT_SDKS#yes}
ARG _PARSE_USE_SWIFT_SDKS=${_PARSE_USE_SWIFT_SDKS#1}
# if not empty, USE_SWIFT_SDKS is false, do not install swift sdks
ARG SWIFT_SDKS_SELECTOR=${_PARSE_USE_SWIFT_SDKS:+dependencies}
# if empty, USE_SWIFT_SDKS is true, install swift sdks
ARG SWIFT_SDKS_SELECTOR=${SWIFT_SDKS_SELECTOR:-swift-sdks}

####################################################################################################
# helpser scripts
####################################################################################################
# apt-get-update
FROM scratch AS apt-get-update
COPY --chmod=755 <<'EOF' apt-get-update
#!/bin/bash -eu
    # do not clean apt cache
    [[ ! -f /etc/apt/apt.conf.d/docker-clean ]] || (
        cd /etc/apt/apt.conf.d; rm -f docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > keep-cache
    )

    # check pkgcache.bin is up-to-date or run apt-get update
    apt_cache_dir=/var/cache/apt
    apt_pkgcache=pkgcache.bin
    apt_sources_dir=/etc/apt/sources.list.d/
    source <(apt-config shell apt_cache_dir Dir::Cache/d apt_pkgcache Dir::Cache::pkgcache apt_sources_dir Dir::Etc::sourceparts/d)
    [[ -f "${apt_cache_dir}${apt_pkgcache}" &&
        -n "$(find "${apt_cache_dir}" -name "${apt_pkgcache}" -mmin -120)" &&
        -z "$(find "${apt_sources_dir}" -newer "${apt_cache_dir}${apt_pkgcache}")" ]] || apt-get update -qq
    [[ ${#@} -eq 0 ]] || apt-get "$@"
EOF

COPY --chmod=755 <<'EOF' apt-get-install
#!/bin/bash -eux
    apt-get-update install --no-install-recommends -qq "$@" >/dev/null
EOF

# github-release-artifact-with-pattern
FROM scratch AS github-release-artifact-with-pattern
COPY --chmod=755 <<'EOF' github-release-artifact-with-pattern
#!/bin/bash -eu
    arch_pattern="$(arch)"
    arch_pattern="${arch_pattern/aarch64/"(aarch64|arm64)"}"
    arch_pattern="${arch_pattern/x86_64/"(amd64|x86_64)"}"
    pattern="${2/$(arch)/${arch_pattern}}"
    download_url=$(gh release view --json assets --repo "${1}" "${3:-}" --jq '.assets|map(.url|select(test("'"${pattern}"'")))|first')
    curl -fLsS "${download_url}" -o -
EOF

# install-gh
FROM scratch AS install-gh
COPY --chmod=755 <<'EOF' install-gh
#!/bin/bash -eu
    keyring=/etc/apt/keyrings/githubcli-archive-keyring.gpg
    packages_url="https://cli.github.com/packages"
    [[ -f ${keyring} ]] || curl -fLsS "${packages_url}/$(basename "${keyring}")" -o "${keyring}" --create-dirs
    list=/etc/apt/sources.list.d/github-cli.list
    [[ -f ${list} ]] || echo "deb [arch=$(dpkg --print-architecture) signed-by=${keyring}] ${packages_url} stable main" >"${list}"
    apt-get-install gh
    gh --version
EOF

####################################################################################################
# swift-toolchain-downloader
####################################################################################################
FROM ${PLATFORM_IMAGE} AS swift-toolchain-downloader
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]
ARG TARGETARCH

# install /usr/local/bin/apt-get-update script
COPY --from=apt-get-update /* /usr/local/bin/

# download Swift toolchain
ARG SWIFT_PLATFORM #=ubuntu
ARG OS_MAJOR_VER #=24
ARG OS_MIN_VER #=04
ARG SWIFT_WEBROOT #=https://download.swift.org/development

WORKDIR /swift-toolchain
RUN --mount=type=cache,sharing=locked,target=/var/cache/apt,id=${TARGETARCH} --mount=type=cache,sharing=locked,target=/var/lib/apt,id=${TARGETARCH} <<EOF
    case $(arch) in
    x86_64) OS_ARCH_SUFFIX='' ;;
    aarch64) OS_ARCH_SUFFIX='-aarch64' ;;
    *) echo >&2 "error: unsupported architecture: '$(arch)'"; exit 1 ;;
    esac
    PLATFORM_WEBROOT="${SWIFT_WEBROOT}/${SWIFT_PLATFORM}${OS_MAJOR_VER}${OS_MIN_VER}${OS_ARCH_SUFFIX}"
    latest_build_yml="${PLATFORM_WEBROOT}/latest-build.yml"
    echo "${latest_build_yml}"

    # - Grab curl here so we cache better up above
    apt-get-install ca-certificates curl gnupg2

    # - Latest Toolchain info
    source <(curl -s "${latest_build_yml}" | sed -E 's/^([^:]+): +(.*)$/\1="\2"/')
    [[ -n ${dir} && -n ${download} && -n ${download_signature} ]] || exit
    echo "${dir}" >.swift_tag
    download_url_base="${PLATFORM_WEBROOT}/${dir}"

    # - Download the GPG keys, Swift toolchain, and toolchain signature, and verify.
    export GNUPGHOME=.
    curl -fLsS --compressed https://swift.org/keys/all-keys.asc | gpg --import --quiet - >/dev/null
    curl -fLsS "${download_url_base}/${download}" -O "${download_url_base}/${download_signature}" -O
    gpg --batch --quiet --verify "${download_signature}" "${download}" >/dev/null
    apt-get-update purge --auto-remove -qq curl gnupg2 >/dev/null
    ln -sf "${download}" latest_toolchain.tar.gz
EOF

####################################################################################################
# swift-sdks-downloader
####################################################################################################
FROM ${PLATFORM_IMAGE} AS swift-sdks-downloader
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]
ARG TARGETARCH

# install /usr/local/bin/apt-get-update script
COPY --from=apt-get-update /* /usr/local/bin/

# download Swift SDKs
WORKDIR /swift-sdks
COPY swift-sdks.txt ./
RUN --mount=type=cache,sharing=locked,target=/var/cache/apt,id=${TARGETARCH} --mount=type=cache,sharing=locked,target=/var/lib/apt,id=${TARGETARCH} <<EOF
    swift_sdks_txt=$(cat swift-sdks.txt)
    rm swift-sdks.txt
    [ -z "${swift_sdks_txt}" ] && exit
    apt-get-install ca-certificates curl
    echo -n "${swift_sdks_txt}" | while read -r sha256 url; do
        curl -fLsS "${url}" -O -w "${sha256} %{filename_effective}\n" | sha256sum --check --strict -
    done
EOF

####################################################################################################
# use-pre-built-swift-image
####################################################################################################
FROM ${DOCKER_IMAGE} AS use-pre-built-swift-image
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]
ARG TARGETARCH

# install /usr/local/bin/apt-get-update script
COPY --from=apt-get-update /* /usr/local/bin/

####################################################################################################
# use-swift-snapshot-image-built-here
####################################################################################################
# Based on https://github.com/swiftlang/swift-docker/blob/main/nightly-main/ubuntu/22.04/buildx/Dockerfile
FROM ${PLATFORM_IMAGE} AS use-swift-snapshot-image-built-here
# LABEL maintainer="Swift Infrastructure <swift-infrastructure@forums.swift.org>"
# LABEL description="Docker Container for the Swift programming language"
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]
ARG TARGETARCH

# install /usr/local/bin/apt-get-update script
COPY --from=apt-get-update /* /usr/local/bin/

# install apt dependencies
RUN --mount=type=cache,sharing=locked,target=/var/cache/apt,id=${TARGETARCH} --mount=type=cache,sharing=locked,target=/var/lib/apt,id=${TARGETARCH} \
    apt-get-install \
    binutils \
    git \
    unzip \
    gnupg2 \
    libc6-dev \
    libcurl4-openssl-dev \
    libedit2 \
    libgcc-12-dev \
    libpython3-dev \
    libsqlite3-0 \
    libstdc++-12-dev \
    libxml2-dev \
    libncurses-dev \
    libz3-dev \
    pkg-config \
    tzdata \
    zlib1g-dev

# Unpack the toolchain, set libs permissions.
RUN --mount=type=bind,from=swift-toolchain-downloader,source=/swift-toolchain,target=/swift-toolchain \
    tar -xzf /swift-toolchain/latest_toolchain.tar.gz --directory / --no-same-owner --strip-components=1 && \
    chmod -R o+r /usr/lib/swift && \
    cp -p /swift-toolchain/.swift_tag /

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
# wasmkit-builder
####################################################################################################
FROM swift:${PLATFORM_CODENAME} AS wasmkit-builder
SHELL ["/bin/bash", "-eu", "-o", "pipefail", "-c"]
ARG TARGETARCH

# install /usr/local/bin/apt-get-update script
COPY --from=apt-get-update /* /usr/local/bin/

# install curl and jq
RUN --mount=type=cache,sharing=locked,target=/var/cache/apt,id=${TARGETARCH} --mount=type=cache,sharing=locked,target=/var/lib/apt,id=${TARGETARCH} \
    apt-get-install ca-certificates curl jq

# install yq
COPY --from=mikefarah/yq /usr/bin/yq /usr/local/bin/

ARG WASMKIT_BUILDER=/wasmkit-builder
WORKDIR ${WASMKIT_BUILDER}
RUN --mount=type=cache,target=/root/.cache --mount=type=tmpfs,target=${WASMKIT_BUILDER} --mount=type=cache,target=${WASMKIT_BUILDER}/.build <<'EOF'
    # detect the latest wasmkit release tag
    tag=$(curl -fLsS "https://github.com/swiftwasm/wasmkit/releases/latest" -H'Accept: application/json' | jq -r .tag_name)

    # download wasmkit source code
    curl -fLsS "https://github.com/swiftwasm/wasmkit/archive/refs/tags/${tag}.tar.gz" | tar zxf - --no-same-owner --strip-component=1

    # build wasmkit-cli
    BUILD_FLAGS=(--static-swift-stdlib -c release --product wasmkit-cli)
    swift build "${BUILD_FLAGS[@]}"
    install -D -t /usr/bin "$(swift build --show-bin-path "${BUILD_FLAGS[@]}")/wasmkit-cli"
    wasmkit-cli --version
EOF

####################################################################################################
# prepare-dependencies
####################################################################################################
FROM use-${SWIFT_IMAGE_SELECTOR} AS prepare-dependencies

# setup user account for running bot
ARG USERNAME=bot
RUN mkdir -p /etc/skel/.cache/deno && useradd -m $USERNAME

# install tools
WORKDIR /usr/local/bin

# install apt dependencies
RUN --mount=type=cache,sharing=locked,target=/var/cache/apt,id=${TARGETARCH} --mount=type=cache,sharing=locked,target=/var/lib/apt,id=${TARGETARCH} \
    apt-get-install ca-certificates curl file jq time unzip xz-utils

# install llvm-symbolizer
RUN --mount=type=cache,sharing=locked,target=/var/cache/apt,id=${TARGETARCH} --mount=type=cache,sharing=locked,target=/var/lib/apt,id=${TARGETARCH} <<'EOF'
    # Use apt-patterns(7) to search llvm-[0-9]+ package that is depended by llvm package
    apt_patterns_for_llvm='?and(?reverse-depends(?exact-name(llvm)),?name(llvm-[0-9]+))'

    # get deb by --print-uris before `cd`, since it fails if the deb already exists in the current directory
    read -r _uri deb _hash < <(apt-get-update download --print-uris "${apt_patterns_for_llvm}")

    # cd to the cache directory
    source <(apt-config shell apt_cache_archives_dir Dir::Cache::archives/d)
    mkdir -p "${apt_cache_archives_dir}"
    cd "${apt_cache_archives_dir}" # Since the deb may exist in the cache, change the directory after get deb

    # download llvm-[0-9]+ package which contains llvm-symbolizer
    apt-get-update download -qq "${apt_patterns_for_llvm}" # download will success whether the deb exists or not

    # extract llvm-symbolizer binary to /usr/local/bin
    dest=/usr/local/bin/llvm-symbolizer
    to_command="bash -c '[[ \$TAR_FILENAME != */llvm-symbolizer ]] || (cat >${dest} && chmod \$TAR_MODE ${dest})'"
    dpkg --fsys-tarfile "${deb}" | tar xf - --to-command="${to_command}"

    # install libllvm* package which is required by llvm-symbolizer
    libllvm=$(apt-cache depends --important --recurse llvm|grep '^libllvm.*$')
    apt-get-install "${libllvm}"
EOF

# install gh
RUN --mount=type=cache,sharing=locked,target=/var/cache/apt,id=${TARGETARCH} --mount=type=cache,sharing=locked,target=/var/lib/apt,id=${TARGETARCH} \
    --mount=type=bind,from=install-gh,source=/install-gh,target=/usr/local/bin/install-gh \
    install-gh

# install github-release-artifact-with-pattern script
COPY --from=github-release-artifact-with-pattern github-release-artifact-with-pattern /usr/local/bin/

# install deno
RUN --mount=type=secret,id=github_token,env=GITHUB_TOKEN <<EOF
    github-release-artifact-with-pattern "denoland/deno" 'deno-'"$(arch)"'-unknown-linux-gnu.zip$' v1.46.3 | funzip >deno
    chmod +x deno
    deno --version
EOF

# install swift-* wrapper scripts
COPY --chmod=755 swift-wrappers/swift-+ /usr/bin/

# create symbolic links to swift-+
RUN /usr/bin/swift-+ --install-shortcuts

####################################################################################################
# prepare-swift-sdks
####################################################################################################
FROM prepare-dependencies AS prepare-swift-sdks

USER root
WORKDIR /usr/local/bin

# install wasmer
RUN --mount=type=secret,id=github_token,env=GITHUB_TOKEN <<EOF
    github-release-artifact-with-pattern "wasmerio/wasmer" 'linux-'"$(arch)"'.tar.gz$' v6.0.0-alpha.2 | tar xzf - --directory .. --no-same-owner
    wasmer-headless --version
EOF

# install wasmkit-cli
COPY --from=wasmkit-builder /usr/bin/wasmkit-cli /usr/local/bin/

# install wasmtime
RUN --mount=type=secret,id=github_token,env=GITHUB_TOKEN <<EOF
    github-release-artifact-with-pattern "bytecodealliance/wasmtime" "$(arch)"'-linux.tar.xz$' | tar xJf - --no-same-owner --strip-components=1 --wildcards "*/wasmtime"
    wasmtime --version
EOF

# install wazero
RUN --mount=type=secret,id=github_token,env=GITHUB_TOKEN <<EOF
    github-release-artifact-with-pattern "tetratelabs/wazero" 'linux_'"$(arch)"'.tar.gz$' | tar xzf - --no-same-owner
    wazero version
EOF

# Install SwiftSDKs on the bot user
USER $USERNAME
RUN --mount=type=bind,from=swift-sdks-downloader,source=/swift-sdks,target=/swift-sdks \
    find /swift-sdks -type f | xargs -n 1 -r swift sdk install

####################################################################################################
# development stage for developing bot in devcontainer on VSCode
####################################################################################################
FROM prepare-${SWIFT_SDKS_SELECTOR} AS debugger

ARG DEBUGGER_USERNAME=debugger
USER root

COPY --from=apt-get-update /* /usr/local/bin/

# Setup for debugging in VSCode
RUN --mount=type=cache,sharing=locked,target=/var/cache/apt,id=${TARGETARCH} --mount=type=cache,sharing=locked,target=/var/lib/apt,id=${TARGETARCH} <<EOF
    # Install git and sudo
    apt-get-install git shellcheck shfmt sudo

    # Create a user for debugging
    useradd -m "${DEBUGGER_USERNAME}"
    echo "${DEBUGGER_USERNAME} ALL=(${USERNAME}) NOPASSWD:ALL" >"/etc/sudoers.d/${DEBUGGER_USERNAME}"
    chmod 0440 "/etc/sudoers.d/${DEBUGGER_USERNAME}"

    # override scripts with symbolic links against the workspace
    scripts=( + )
    for override in "${scripts[@]}"; do
        ln -sf "/workspaces/swift_discord_bot/swift-wrappers/swift-${override}" "/usr/bin/swift-${override}"
    done
EOF

USER ${DEBUGGER_USERNAME}

####################################################################################################
# production stage for running bot on production
####################################################################################################
FROM prepare-${SWIFT_SDKS_SELECTOR} AS production

# use the bot user
USER $USERNAME

# Install Bot Source Code
WORKDIR /bot

# Cache Dependencies
COPY deps.ts ./
RUN <<'EOF'
    DENO_ARGS=(--quiet)
    [[ "$(deno -v)" == "deno 1."* ]] || DENO_ARGS+=(
        "--allow-import=deno.land:443,raw.githubusercontent.com:443,unpkg.com:443"
    )
    deno cache "${DENO_ARGS[@]}" ./deps.ts
EOF

# Install remains
COPY bot.ts entrypoint.sh ./

# Start Bot
ENTRYPOINT [ "./entrypoint.sh" ]
