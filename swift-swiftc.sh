#!/bin/bash
set -eu
case "${1:-}" in
-*)
	swiftc "$@"
	;;
*)
	command="${1}"
	"swift-${command}" "${@:2}"
	;;
esac
status=$?
[[ -x main ]] || exit $status
file_info="$(file -b main)"
case "${file_info}" in
ELF* | Mach-O*)
	./main "$@"
	status=$?
	rm main
	exit $status
	;;
WebAssembly*)
	wasmtime main "$@"
	status=$?
	rm main
	exit $status
	;;
*)
	echo "main is not an executable file: ${file_info}" >&2
	exit 1
	;;
esac
