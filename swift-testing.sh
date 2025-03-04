#!/bin/bash
set -eu
code="$(cat)"
grep -q "^import Testing$" <<<"${code}" || code="import Testing

${code}"
if [[ " $* " == *" -parse-as-library "* ]]; then
	code="$(
		cat <<-EOF
			${code}
			@main struct Runner {
				static func main() async {
					await Testing.__swiftPMEntryPoint() as Never
				}
			}
		EOF
	)"
else
	code="$(
		cat <<-EOF
			${code}

			await Testing.__swiftPMEntryPoint() as Never
		EOF
	)"
fi

case "${1:-}" in
-*)
	swift-swiftc "$@" <<<"${code}"
	;;
*)
	command="${1}"
	"swift-${command}" swiftc "${@:2}" <<<"${code}"
	;;
esac
