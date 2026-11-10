#!/usr/bin/env bash
# Builds Block Royale for Linux and Windows.
#
#   ./build.sh            build both
#   ./build.sh linux      only Linux
#   ./build.sh windows    only Windows
#
# Needs: bash, curl, unzip. Godot 4.7.1 and its export templates are
# downloaded on first run (about 1.3 GB for the templates) unless you already
# have them. Output goes to build/linux and build/windows, plus a zip of each.
set -euo pipefail

GODOT_VERSION="4.7.1"
GODOT_TAG="${GODOT_VERSION}-stable"
RELEASES="https://github.com/godotengine/godot/releases/download/${GODOT_TAG}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS="${ROOT}/.tools"
cd "${ROOT}"

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
	TARGETS=(linux windows)
fi

log() { printf '\033[1;33m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

for cmd in curl unzip; do
	command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' is required"
done

# --------------------------------------------------------------- platform ----
case "$(uname -s)" in
	Linux*)
		GODOT_ZIP="Godot_v${GODOT_TAG}_linux.x86_64.zip"
		GODOT_BIN_NAME="Godot_v${GODOT_TAG}_linux.x86_64"
		TEMPLATES_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION}.stable"
		;;
	Darwin*)
		GODOT_ZIP="Godot_v${GODOT_TAG}_macos.universal.zip"
		GODOT_BIN_NAME="Godot.app/Contents/MacOS/Godot"
		TEMPLATES_DIR="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable"
		;;
	MINGW*|MSYS*|CYGWIN*)
		GODOT_ZIP="Godot_v${GODOT_TAG}_win64.exe.zip"
		GODOT_BIN_NAME="Godot_v${GODOT_TAG}_win64_console.exe"
		TEMPLATES_DIR="${APPDATA}/Godot/export_templates/${GODOT_VERSION}.stable"
		;;
	*)
		die "unsupported OS: $(uname -s)"
		;;
esac

# ------------------------------------------------------------------ godot ----
find_godot() {
	if [ -n "${GODOT:-}" ] && [ -x "${GODOT}" ]; then
		echo "${GODOT}"
		return
	fi
	if [ -x "${TOOLS}/${GODOT_BIN_NAME}" ]; then
		echo "${TOOLS}/${GODOT_BIN_NAME}"
		return
	fi
	for c in godot godot4 Godot; do
		if command -v "$c" >/dev/null 2>&1 && "$c" --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable"; then
			command -v "$c"
			return
		fi
	done
}

GODOT_BIN="$(find_godot || true)"
if [ -z "${GODOT_BIN}" ]; then
	log "Downloading Godot ${GODOT_VERSION}"
	mkdir -p "${TOOLS}"
	curl -fL --progress-bar -o "${TOOLS}/${GODOT_ZIP}" "${RELEASES}/${GODOT_ZIP}"
	unzip -q -o "${TOOLS}/${GODOT_ZIP}" -d "${TOOLS}"
	rm -f "${TOOLS}/${GODOT_ZIP}"
	GODOT_BIN="${TOOLS}/${GODOT_BIN_NAME}"
	chmod +x "${GODOT_BIN}" 2>/dev/null || true
fi
log "Using $("${GODOT_BIN}" --version | head -1) at ${GODOT_BIN}"

# -------------------------------------------------------------- templates ----
if [ ! -f "${TEMPLATES_DIR}/linux_release.x86_64" ] || [ ! -f "${TEMPLATES_DIR}/windows_release_x86_64.exe" ]; then
	log "Downloading export templates (~1.3 GB, only needed once)"
	mkdir -p "${TOOLS}" "${TEMPLATES_DIR}"
	TPZ="${TOOLS}/templates.tpz"
	curl -fL --progress-bar -o "${TPZ}" "${RELEASES}/Godot_v${GODOT_TAG}_export_templates.tpz"
	rm -rf "${TOOLS}/templates_unpack"
	unzip -q -o "${TPZ}" -d "${TOOLS}/templates_unpack"
	cp -f "${TOOLS}/templates_unpack/templates/"* "${TEMPLATES_DIR}/"
	rm -rf "${TOOLS}/templates_unpack" "${TPZ}"
fi

# ------------------------------------------------------------------ build ----
log "Importing assets"
"${GODOT_BIN}" --headless --path "${ROOT}" --import >/dev/null 2>&1 || true

export_one() {
	local preset="$1" out="$2"
	mkdir -p "$(dirname "${out}")"
	rm -f "${out}"
	log "Exporting ${preset} -> ${out#${ROOT}/}"
	"${GODOT_BIN}" --headless --path "${ROOT}" --export-release "${preset}" "${out}" 2>&1 \
		| grep -vE "^(\s*$|ALSA|Godot Engine v)|savepack|Storing File|% \]" || true
	[ -f "${out}" ] || die "export of ${preset} failed"
}

for target in "${TARGETS[@]}"; do
	case "${target}" in
		linux)
			export_one "Linux" "${ROOT}/build/linux/BlockRoyale.x86_64"
			chmod +x "${ROOT}/build/linux/BlockRoyale.x86_64"
			(cd "${ROOT}/build" && rm -f BlockRoyale-linux.zip && zip -q -9 -r BlockRoyale-linux.zip linux 2>/dev/null) || true
			;;
		windows)
			export_one "Windows Desktop" "${ROOT}/build/windows/BlockRoyale.exe"
			(cd "${ROOT}/build" && rm -f BlockRoyale-windows.zip && zip -q -9 -r BlockRoyale-windows.zip windows 2>/dev/null) || true
			;;
		*)
			die "unknown target '${target}' (use linux or windows)"
			;;
	esac
done

log "Done:"
ls -lh "${ROOT}/build"/*/BlockRoyale* "${ROOT}/build"/*.zip 2>/dev/null || ls -lh "${ROOT}/build"/*/BlockRoyale*
