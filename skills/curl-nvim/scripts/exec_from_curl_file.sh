#!/usr/bin/env sh
set -eu

usage() {
	cat <<'EOF'
Usage:
  exec_from_curl_file.sh --file <path> [options]

Options:
  --line <n>              Cursor line in .curl file (default: 1)
  --mode <export|exec>    Operation mode (default: exec)
  --show-stderr           Include stderr before stdout on success
  --print-command         Print resolved command to stderr before execute
  --root-anchor <dir>     Base directory for relative ---source paths
  --plugin-dir <dir>      curl.nvim plugin directory (required unless CURL_NVIM_PLUGIN_DIR is set)
  --curl-binary <name>    Replace leading curl alias (optional)
  -h, --help              Show this help
EOF
}

die() {
	echo "error: $*" >&2
	exit 2
}

mode="exec"
line="1"
file_path=""
plugin_dir="${CURL_NVIM_PLUGIN_DIR:-}"
root_anchor=""
show_stderr="0"
print_command="0"
curl_binary=""

while [ "$#" -gt 0 ]; do
	case "$1" in
	--file)
		[ "$#" -ge 2 ] || die "--file requires a value"
		file_path="$2"
		shift 2
		;;
	--line)
		[ "$#" -ge 2 ] || die "--line requires a value"
		line="$2"
		shift 2
		;;
	--mode)
		[ "$#" -ge 2 ] || die "--mode requires a value"
		mode="$2"
		shift 2
		;;
	--plugin-dir)
		[ "$#" -ge 2 ] || die "--plugin-dir requires a value"
		plugin_dir="$2"
		shift 2
		;;
	--root-anchor)
		[ "$#" -ge 2 ] || die "--root-anchor requires a value"
		root_anchor="$2"
		shift 2
		;;
	--show-stderr)
		show_stderr="1"
		shift 1
		;;
	--print-command)
		print_command="1"
		shift 1
		;;
	--curl-binary)
		[ "$#" -ge 2 ] || die "--curl-binary requires a value"
		curl_binary="$2"
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die "unknown option: $1"
		;;
	esac
done

[ -n "$file_path" ] || die "--file is required"

case "$mode" in
export | exec) ;;
*)
	die "--mode must be export or exec"
	;;
esac

case "$line" in
'' | *[!0-9]*)
	die "--line must be a positive integer"
	;;
esac
[ "$line" -ge 1 ] || die "--line must be >= 1"

if [ ! -f "$file_path" ]; then
	die "file not found: $file_path"
fi

file_path="$(cd "$(dirname "$file_path")" && pwd -P)/$(basename "$file_path")"

[ -n "$plugin_dir" ] || die "plugin dir is required; pass --plugin-dir or set CURL_NVIM_PLUGIN_DIR"

if [ ! -d "$plugin_dir" ] || [ ! -f "$plugin_dir/lua/curl/api.lua" ]; then
	die "invalid plugin dir: $plugin_dir"
fi

plugin_dir="$(cd "$plugin_dir" && pwd -P)"

if [ -n "$root_anchor" ]; then
	case "$root_anchor" in
	\~)
		root_anchor="$HOME"
		;;
	\~/*)
		root_anchor="$HOME/${root_anchor#\~/}"
		;;
	esac
	if [ ! -d "$root_anchor" ]; then
		die "root anchor is not a directory: $root_anchor"
	fi
	root_anchor="$(cd "$root_anchor" && pwd -P)"
fi

command -v nvim >/dev/null 2>&1 || die "nvim is required"

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)"

nvim --headless -u NONE -n -l "$script_dir/exec_from_curl_file.lua" \
	"$plugin_dir" \
	"$mode" \
	"$file_path" \
	"$line" \
	"$root_anchor" \
	"$show_stderr" \
	"$print_command" \
	"$curl_binary"
