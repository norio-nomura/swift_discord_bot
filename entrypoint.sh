#!/bin/bash

echo "RENDER_INSTANCE_ID: ${RENDER_INSTANCE_ID}"

nickname() {
    local swift_version_output
    swift_version_output=$(swift -version 2>/dev/null) || return
    local nickname=$(echo "${swift_version_output}"|sed -n 's/^Swift version \(.*\) (.*)$/\1/p')
    test -n "${nickname}" && echo swift-${nickname}
}

swift_version() {
    swift_release_version || swift_snapshot_version || echo "Failed to detect Swift version"
}

swift_release_version() {
    local swift_version_output
    swift_version_output=$(swift -version 2>/dev/null) || return
    local swift_release_version=$(echo "${swift_version_output}"|sed -n 's/^Swift version .* (\(.*-RELEASE\))$/\1/p')
    test -n "${swift_release_version}" && echo ${swift_release_version}
}

swift_snapshot_version() {
    gh extension install norio-nomura/gh-query-tags 2>/dev/null || return
    swift -version 2>/dev/null | gh query-tags --repo apple/swift
}

export DISCORD_NICKNAME=${DISCORD_NICKNAME:-$(nickname)}
test -z "${DISCORD_NICKNAME}" && unset DISCORD_NICKNAME
export DISCORD_PLAYING=${DISCORD_PLAYING:-$(swift_version)}
test -z "${DISCORD_PLAYING}" && unset DISCORD_PLAYING
export TARGET_CLI=${TARGET_CLI:-swift}
export TARGET_ARGS_TO_USE_STDIN=-

vars=()
for v in DENO_TLS_CA_STORE HTTP_PROXY HTTPS_PROXY PATH PORT; do
    vars=("${vars[@]}" "${!v+${v}=${!v}}")
done

# Avoid passing options via environment variables or comandline arguments
exec env -i ${vars[@]} deno run \
    --allow-env=PATH,PORT \
    --allow-net \
    --allow-run=/usr/bin/env \
    --allow-read=${TMPDIR:-/tmp} \
    --allow-write=${TMPDIR:-/tmp} \
    --quiet \
    "$@" \
    bot.ts <<EOF
$(deno eval 'import { printOptionsFromEnv } from "./deps.ts"; printOptionsFromEnv();')
EOF
