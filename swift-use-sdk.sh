#!/bin/bash
set -eu -o pipefail

# print the error message and exit with status 1
function error_exit() {
	echo "Error: $*" >&2
	exit 1
}

arch=$(arch)
arch=${arch/aarch64/arm64}
target_sys=${0/*\/swift-/}
if [[ ${1:-} == "--list-targets" ]]; then
	echo ios iphone ios-simulator iphonesimulator macos ios-macabi iosmac mac-catalyst wasi wasip1 wasm wasm32 musl static
	exit
elif [[ ${1:-} =~ [0-9]+\.[0-9]+ ]]; then
	deployment_target="${1}"
	shift
else
	deployment_target=""
fi

SWIFT_ARGS_FOR_SDK=()

case "${target_sys}" in
ios | iphone)
	swift_sdk_name=darwin
	darwin_target="iphoneos"
	sdk_triple="${arch}-apple-ios"
	target_triple="${arch}-apple-ios{deployment_target}"
	;;
ios-simulator | iphonesimulator)
	swift_sdk_name=darwin
	darwin_target="iphonesimulator"
	sdk_triple="${arch}-apple-ios-simulator"
	target_triple="${arch}-apple-ios{deployment_target}-simulator"
	;;
macos)
	swift_sdk_name=darwin
	darwin_target="macosx"
	sdk_triple="${arch}-apple-macosx"
	target_triple="${arch}-apple-macosx{deployment_target}"
	;;
ios-macabi | iosmac | mac-catalyst)
	swift_sdk_name=darwin
	darwin_target="iosmac"
	sdk_triple="${arch}-apple-macosx"
	target_triple="${arch}-apple-ios{deployment_target}-macabi"
	;;
wasi | wasip1 | wasm | wasm32)
	sdk_triple="wasm32-unknown-wasi"
	swift_sdk_name=$(swift sdk list | grep -E "${sdk_triple}") || error_exit "No SDK found for ${sdk_triple}"
	target_triple="${sdk_triple}"
	SWIFT_ARGS_FOR_SDK+=(swiftc)
	;;
musl | static)
	swift_sdk_name=$(swift sdk list | grep -E "_static-linux") || error_exit "No SDK found for static-linux"
	sdk_triple="$(arch)-swift-linux-musl"
	target_triple="${sdk_triple}"
	;;
*)
	error_exit "Unknown target: ${target_sys}"
	;;
esac

sdk_configuration=$(swift sdk configure --show-configuration "${swift_sdk_name}" "${sdk_triple}" | yq -o=json) ||
	error_exit "Failed to get configuration for ${swift_sdk_name} ${sdk_triple}"

# Detect deployment target from SDKSettings.json if swift_sdk_name is darwin
if [[ ${swift_sdk_name} == "darwin" && -z ${deployment_target} ]]; then
	sdk_root_path=$(jq -r '.sdkRootPath' <<<"${sdk_configuration}")
	sdk_settings="${sdk_root_path}/SDKSettings.json"
	if [[ -f ${sdk_settings} ]]; then
		deployment_target=$(jq -r '.SupportedTargets.'"${darwin_target}"'.DefaultDeploymentTarget' "${sdk_settings}")
	fi
fi
target_triple=${target_triple//\{deployment_target\}/${deployment_target}}
SWIFT_ARGS_FOR_SDK+=(-target "${target_triple}")

# Build SWIFT_ARGS_FOR_SDK from configuration by jq
jq_output=$(
	jq -r '
        if .includeSearchPaths|type == "array" then (.includeSearchPaths[]|("-I",.)) else empty end
        , if .librarySearchPaths|type == "array" then (.librarySearchPaths[]|("-L",.)) else empty end
        , if .swiftStaticResourcesPath|type == "string" then ("-resource-dir",.swiftStaticResourcesPath+"/clang"|("-Xclang-linker",.)) else empty end
        , "-resource-dir",.swiftResourcesPath
        , "-sdk",.sdkRootPath
        , ("-isysroot",.sdkRootPath|("-Xclang-linker",.))
    ' <<<"${sdk_configuration}"
) || error_exit "Failed to parse SDK configuration"
while IFS= read -r line; do SWIFT_ARGS_FOR_SDK+=("${line}"); done <<<"${jq_output}"
jq_output=$(
	for toolsetPath in $(jq -r '.toolsetPaths[]' <<<"${sdk_configuration}"); do
		jq -r '
            ("'"$(dirname "${toolsetPath}")"'/" + .rootPath) as $rootPath
            | if .linker?.path then "-ld-path=" + $rootPath + "/" + .linker.path else empty end
            , ("-tools-directory",$rootPath|("-Xfrontend",.))
            , (.swiftCompiler?.extraCLIOptions[]?)
            , (.cCompiler?.extraCLIOptions[]?|("-Xcc",.))
            , (.cxxCompiler?.extraCLIOptions[]?|("-Xcxx",.))
            , (.linker?.extraCLIOptions[]?|("-Xlinker",.))
        ' "${toolsetPath}" || error_exit "Failed to parse ${toolsetPath}"
	done
) || error_exit "Failed to parse toolsetPaths"
while IFS= read -r line; do SWIFT_ARGS_FOR_SDK+=("${line}"); done <<<"${jq_output}"

echo "Target: ${target_triple}" >&2
case "${1:-}" in
-*)
	case "${SWIFT_ARGS_FOR_SDK[0]:-}" in
	-*)
		exec swift "${SWIFT_ARGS_FOR_SDK[@]}" "$@"
		;;
	*)
		command="${SWIFT_ARGS_FOR_SDK[0]}"
		exec "swift-${command}" "${SWIFT_ARGS_FOR_SDK[@]:1}" "$@"
		;;
	esac
	;;
*)
	command="${1}"
	exec "swift-${command}" "${SWIFT_ARGS_FOR_SDK[@]}" "${@:2}"
	;;
esac
