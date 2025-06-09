#!/bin/bash

nickname() {
	local swift_version_output
	swift_version_output=$(swift -version 2>/dev/null) || return
	local nickname=$(echo "${swift_version_output}" | sed -n 's/^Swift version \(.*\) (.*)$/\1/p')
	test -n "${nickname}" && echo swift-${nickname}
}

swift_version() {
	swift_release_version || swift_snapshot_version || echo "Failed to detect Swift version"
}

swift_release_version() {
	local swift_version_output
	swift_version_output=$(swift -version 2>/dev/null) || return
	local swift_release_version=$(echo "${swift_version_output}" | sed -n 's/^Swift version .* (\(.*-RELEASE\))$/\1/p')
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
export TARGET_ARGS_TO_USE_STDIN=${TARGET_ARGS_TO_USE_STDIN:--}

allowed_env_keys=(
	ATTACHMENT_EXTENSION_TO_TREAT_AS_INPUT
	DISCORD_NICKNAME
	DISCORD_PLAYING
	DISCORD_TOKEN
	ENV_COMMAND
	HTTP_PROXY
	HTTPS_PROXY
	NUMBER_OF_LINES_TO_EMBED_OUTPUT
	NUMBER_OF_LINES_TO_EMBED_UPLOADED_OUTPUT
	PATH
	REST_TIMEOUT_SECONDS
	TARGET_ARGS_TO_USE_STDIN
	TARGET_CLI
	TARGET_DEFAULT_ARGS
	TIMEOUT_SECONDS
)
vars=()
for v in "${allowed_env_keys[@]}"; do
	test -n "${!v}" && vars=("${vars[@]}" "${!v+${v}=${!v}}")
done

exec env -i "${vars[@]}" /usr/local/bin/cli_discord_bot2
