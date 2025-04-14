#!/bin/bash
set -eu -o pipefail

for c in gh jq yq; do
	command -v "${c}" >/dev/null || {
		echo "${c} is required to run this script. Please install ${c}."
		exit 1
	}
done

gh extension install norio-nomura/gh-query-tags 2>/dev/null

function detect_swift_snapshot_version() {
	local dockerfile="Dockerfile" render_yaml="${1}" SWIFT_WEBROOT SWIFT_PLATFORM PLATFORM_CODENAME OS_MAJOR_VER OS_MIN_VER OS_ARCH_SUFFIX arch latest_build_yml_url

	SWIFT_WEBROOT="$(yq eval '
		.services[0]|.envVars|map(select(.key == "SWIFT_WEBROOT"))[0]|.value // "https://download.swift.org/development"
	' "${render_yaml}")"
	SWIFT_PLATFORM="$(sed -n -E 's/^ARG SWIFT_PLATFORM=(.*)$/\1/p' "${dockerfile}")"
	PLATFORM_CODENAME="$(sed -n -E 's/^ARG PLATFORM_CODENAME=(.*)$/\1/p' "${dockerfile}")"
	OS_MAJOR_VER=${PLATFORM_CODENAME}
	OS_MAJOR_VER=${OS_MAJOR_VER/focal/20}
	OS_MAJOR_VER=${OS_MAJOR_VER/jammy/22}
	OS_MAJOR_VER=${OS_MAJOR_VER/noble/24}
	OS_MIN_VER=${PLATFORM_CODENAME}
	OS_MIN_VER=${OS_MIN_VER/focal/04}
	OS_MIN_VER=${OS_MIN_VER/jammy/04}
	OS_MIN_VER=${OS_MIN_VER/noble/04}
	arch="$(arch)"
	case "${arch}" in
	amd64 | x86_64) OS_ARCH_SUFFIX= ;;
	aarch64 | arm64) OS_ARCH_SUFFIX="-aarch64" ;;
	*)
		echo "Unknown architecture: ${arch}" >&2
		exit 1
		;;
	esac
	latest_build_yml_url="${SWIFT_WEBROOT}/${SWIFT_PLATFORM}${OS_MAJOR_VER}${OS_MIN_VER}${OS_ARCH_SUFFIX}/latest-build.yml"
	curl -fLsS "${latest_build_yml_url}" -o - | yq eval '.dir' -
}

function detect_swift_release_version() {
	local render_yaml="${1}" VERSION_NUMBER
	VERSION_NUMBER="$(yq eval '
		.services[0]|.envVars|map(select(.key == "DOCKER_IMAGE"))[0]
		|.value // ""|capture(":(?P<version>\d+\.\d+(\.\d+)?)")|.version // "latest"
	' "${render_yaml}")"
	[[ ${VERSION_NUMBER} == "latest" ]] && VERSION_NUMBER="$(
		curl -fLsS "https://github.com/swiftlang/swift-org-website/raw/refs/heads/main/_data/builds/swift_releases.yml" | yq e '.[-1].name'
	)"
	echo "swift-${VERSION_NUMBER}-RELEASE"
}

function detect_swift_version_from_render_yaml() {
	local render_yaml="${1}"
	USE_SNAPSHOT="$(yq eval '.services[0]|.envVars|map(select(.key == "USE_SNAPSHOT"))[0]|.value' "${render_yaml}")"
	case "${USE_SNAPSHOT}" in
	"ON" | "on" | "TRUE" | "true" | "YES" | "yes" | "1")
		# swift-(\d+\.\d+-)?DEVELOPMENT-SNAPSHOT-\d+-\d+-\d+-a
		detect_swift_snapshot_version "${render_yaml}"
		;;
	*)
		# swift-\d+\.\d+(.\d+)?-RELEASE
		detect_swift_release_version "${render_yaml}"
		;;
	esac
}

function swift_tag_patterns_from_swift_version() {
	local swift_version="${1}" patterns
	case "${swift_version}" in
	swift-*-RELEASE)
		# if patch version is not specified, use the latest patch version. If patch version is specified, use the exact version.
		patterns=("$(sed -E 's/-([0-9]+\.[0-9]+)-/-\1(\\\\.[0-9]+)?-/' <<<"${swift_version}")")
		# Whether the patch version is specified or not, use the latest patch version.
		patterns+=("$(sed -E 's/-([0-9]+\.[0-9]+)(\.[0-9]+)?-/-\1(\\\\.[0-9]+)?-/' <<<"${swift_version}")")
		# Try to use the latest development snapshot version.
		patterns+=("$(sed -E 's/-([0-9]+\.[0-9]+)(\.[0-9]+)?-RELEASE/-\1-DEVELOPMENT-SNAPSHOT-[0-9]+-[0-9]+-[0-9]+-a/' <<<"${swift_version}")")
		;;
	swift-*DEVELOPMENT-SNAPSHOT-*)
		patterns=("${swift_version}")
		# Try to use the latest development snapshot version.
		patterns+=("$(sed -E 's/-DEVELOPMENT-SNAPSHOT-[0-9]+-[0-9]+-[0-9]+-a/-DEVELOPMENT-SNAPSHOT-[0-9]+-[0-9]+-[0-9]+-a/' <<<"${swift_version}")")
		;;
	*)
		echo "Unexpected Swift version: ${swift_version}" >&2
		exit 1
		;;
	esac
	echo "${patterns[@]}"
}

function query_swiftwasm_tag() {
	local swift_version="${1}" pattern
	for pattern in $(swift_tag_patterns_from_swift_version "${swift_version}"); do
		gh query-tags --repo swiftwasm/swift --use-release "${pattern}" && return
	done
}

function print_swiftsdk_from_swiftwasm_tag() {
	local swiftwasm_tag="${1}" artifactbundle_url
	artifactbundle_url="$(gh release view --repo swiftwasm/swift "${swiftwasm_tag}" --json assets --jq '
		.assets[]|select(.name|endswith("-wasm32-unknown-wasi.artifactbundle.zip"))|.url
	')"
	[[ -n ${artifactbundle_url} ]] && sha256="$(curl -fLsS "${artifactbundle_url}.sha256" -o -)" && echo "${sha256} ${artifactbundle_url}"
}

function print_swiftwasm_sdk_hash_and_url() {
	SWIFTWASM_TAG="$(query_swiftwasm_tag "${1}")"
	[[ -z ${SWIFTWASM_TAG} ]] && return
	print_swiftsdk_from_swiftwasm_tag "${SWIFTWASM_TAG}"
}

function print_swift_static_sdk_development_snapshot_hash_and_url() {
	local pattern static_sdk_yml_url static_sdk_json swift_version="${1}" webroot
	webroot="${swift_version//DEVELOPMENT-SNAPSHOT-*/branch}"
	webroot="$(sed -E 's/^(swift-[0-9]+\.[0-9]+)(\.[0-9]+)?-RELEASE$/\1-branch/' <<<"${webroot}")"
	[[ ${webroot} == swift-branch ]] && webroot="development"
	static_sdk_yml_url="https://github.com/swiftlang/swift-org-website/raw/refs/heads/main/_data/builds/${webroot/\./_}/static_sdk.yml"
	static_sdk_json="$(curl -fLsS "${static_sdk_yml_url}" -o - | yq -o=json -)"
	[[ ${static_sdk_json} == null ]] && return
	for pattern in $(swift_tag_patterns_from_swift_version "${swift_version}"); do
		# shellcheck disable=SC2016,SC2086
		jq -e -r '
			map(select(.dir|test("'${pattern}'")))
			|map("\(.checksum) https://download.swift.org/'"${webroot}"'/static-sdk/\(.dir)/\(.download)")
			|first // empty
		' <<<"${static_sdk_json}" && return
	done
}

function print_swift_static_sdk_release_hash_and_url() {
	local pattern swift_version="${1}" swift_releases_yml_url swift_releases_json
	swift_releases_yml_url="https://github.com/swiftlang/swift-org-website/raw/refs/heads/main/_data/builds/swift_releases.yml"
	swift_releases_json="$(curl -fLsS "${swift_releases_yml_url}" -o - | yq -o=json -)"
	for pattern in $(swift_tag_patterns_from_swift_version "${swift_version}"); do
		# shellcheck disable=SC2016,SC2086
		jq -e -r '
			map(select(.tag|test("'${pattern}'")))|last
			|.tag as $tag
			|[.platforms[]?|select(.platform|test("static-sdk"))]
			|map("\(.checksum) https://download.swift.org/\($tag|ascii_downcase)/static-sdk/\($tag)/\($tag)_static-linux-0.0.1.artifactbundle.tar.gz")
			|last // empty
		' <<<"${swift_releases_json}" && return
	done
	# fallback to development snapshot if the release is not found
	print_swift_static_sdk_development_snapshot_hash_and_url "${swift_version}"
}

function print_swift_static_sdk_hash_and_url() {
	local swift_version="${1}"
	case "${swift_version}" in
	swift-*DEVELOPMENT-SNAPSHOT-*)
		print_swift_static_sdk_development_snapshot_hash_and_url "${swift_version}"
		;;
	swift-*-RELEASE)
		print_swift_static_sdk_release_hash_and_url "${swift_version}"
		;;
	*)
		echo "Unexpected Swift version: ${swift_version}" >&2
		exit 1
		;;
	esac
}

SWIFT_VERSION="${1:-}"
SWIFT_VERSION="${SWIFT_VERSION:-$(detect_swift_version_from_render_yaml "render.yaml")}"
SWIFT_SDKS="$(
	print_swift_static_sdk_hash_and_url "${SWIFT_VERSION}"
	print_swiftwasm_sdk_hash_and_url "${SWIFT_VERSION}"
)"

echo -n "${SWIFT_SDKS}" | tee swift-sdks.txt
