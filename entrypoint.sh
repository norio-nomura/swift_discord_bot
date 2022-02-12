#!/bin/sh

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

# Avoid passing options via environment variables or comandline arguments
options="\
${DISCORD_NICKNAME+DISCORD_NICKNAME: '${DISCORD_NICKNAME}', }\
${DISCORD_PLAYING+DISCORD_PLAYING: '${DISCORD_PLAYING}', }\
${DISCORD_TOKEN+DISCORD_TOKEN: '${DISCORD_TOKEN}', }\
${ENV_ARGS+ENV_ARGS: '${ENV_ARGS}', }\
${ENV_COMMAND+ENV_COMMAND: '${ENV_COMMAND}', }\
${PATH+PATH: '${PATH}', }\
${TARGET_ARGS_TO_USE_STDIN+TARGET_ARGS_TO_USE_STDIN: '${TARGET_ARGS_TO_USE_STDIN}', }\
${TARGET_CLI+TARGET_CLI: '${TARGET_CLI}', }\
${TARGET_DEFAULT_ARGS+TARGET_DEFAULT_ARGS: '${TARGET_DEFAULT_ARGS}', }\
${TIMEOUT_ARGS+TIMEOUT_ARGS: '${TIMEOUT_ARGS}', }\
${TIMEOUT_COMMAND+TIMEOUT_COMMAND: '${TIMEOUT_COMMAND}', }\
"
exec env -i PATH=${PATH} DENO_TLS_CA_STORE=system deno run \
    --allow-env=PATH \
    --allow-net \
    --allow-run=/usr/bin/env \
    --quiet \
- <<EOF
$(awk -v options="${options}" '{sub("// Set options here", options); print}' bot.ts) 
EOF
