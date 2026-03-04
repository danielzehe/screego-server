#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/local-release"
TMP_DIR="$DIST_DIR/.tmp"

VERSION_INPUT=""
SKIP_UI_INSTALL=false
SKIP_UI_BUILD=false
NO_CLEAN=false

usage() {
    cat <<'EOF'
Build local multi-platform screego release artifacts without GitHub Actions.

Usage:
  ./scripts/build-local-release.sh [options]

Options:
  --version <value>     Set artifact version (default: git describe --tags --always --dirty).
  --skip-ui-install     Skip dependency install in ui/.
  --skip-ui-build       Skip ui build step (requires existing ui/build assets).
  --no-clean            Keep existing dist/local-release output.
  -h, --help            Show this help.

Output:
  dist/local-release/screego_<version>_<os>_<arch>.tar.gz
  dist/local-release/screego_<version>_<os>_<arch>.zip (windows targets)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION_INPUT="${2:-}"
            shift 2
            ;;
        --skip-ui-install)
            SKIP_UI_INSTALL=true
            shift
            ;;
        --skip-ui-build)
            SKIP_UI_BUILD=true
            shift
            ;;
        --no-clean)
            NO_CLEAN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

require_cmd go
require_cmd git
require_cmd tar
require_cmd zip

if [[ -n "$VERSION_INPUT" ]]; then
    VERSION="$VERSION_INPUT"
else
    VERSION="$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || true)"
    if [[ -z "$VERSION" ]]; then
        VERSION="snapshot"
    fi
fi
VERSION="${VERSION#v}"
COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"

if [[ "$SKIP_UI_BUILD" == "false" ]]; then
    if [[ "$SKIP_UI_INSTALL" == "false" ]]; then
        if command -v yarn >/dev/null 2>&1; then
            (
                cd "$ROOT_DIR/ui"
                yarn install --frozen-lockfile
            )
        elif command -v npm >/dev/null 2>&1; then
            (
                cd "$ROOT_DIR/ui"
                npm install --legacy-peer-deps --no-package-lock
            )
        else
            echo "Missing required command for ui install: yarn or npm" >&2
            exit 1
        fi
    fi

    if command -v yarn >/dev/null 2>&1; then
        (
            cd "$ROOT_DIR/ui"
            yarn build
        )
    elif command -v npm >/dev/null 2>&1; then
        (
            cd "$ROOT_DIR/ui"
            npm run build
        )
    else
        echo "Missing required command for ui build: yarn or npm" >&2
        exit 1
    fi
fi

if [[ ! -d "$ROOT_DIR/ui/build" ]]; then
    echo "ui/build directory missing. Run without --skip-ui-build or build ui manually first." >&2
    exit 1
fi

if [[ "$NO_CLEAN" == "false" ]]; then
    rm -rf "$DIST_DIR"
fi
mkdir -p "$TMP_DIR"

SUPPORTED_DIST=()
while IFS= read -r line; do
    SUPPORTED_DIST+=("$line")
done < <(go tool dist list)
is_supported() {
    local tuple="$1"
    for item in "${SUPPORTED_DIST[@]}"; do
        if [[ "$item" == "$tuple" ]]; then
            return 0
        fi
    done
    return 1
}

GOOS_TARGETS=(linux windows darwin freebsd openbsd)
GOARCH_TARGETS=(386 amd64 arm64 ppc64 ppc64le)

build_target() {
    local goos="$1"
    local goarch="$2"
    local goarm="${3:-}"
    local arch_label
    local binary_name="screego"
    local archive_name
    local target_dir
    local output_archive
    local ldflags

    arch_label="$goarch"
    if [[ "$goarch" == "386" ]]; then
        arch_label="i386"
    fi
    if [[ "$goarch" == "arm" ]]; then
        arch_label="armv$goarm"
    fi
    if [[ "$goos" == "windows" ]]; then
        binary_name="screego.exe"
    fi

    archive_name="screego_${VERSION}_${goos}_${arch_label}"
    target_dir="$TMP_DIR/$archive_name"
    output_archive="$DIST_DIR/$archive_name"
    ldflags="-s -w -X main.version=$VERSION -X main.commitHash=$COMMIT -X main.mode=prod"

    rm -rf "$target_dir"
    mkdir -p "$target_dir"

    echo "Building ${goos}/${goarch}${goarm:+ (GOARM=$goarm)}"
    (
        cd "$ROOT_DIR"
        if [[ "$goarch" == "arm" ]]; then
            GOOS="$goos" GOARCH="$goarch" GOARM="$goarm" CGO_ENABLED=0 \
                go build -trimpath -tags "netgo osusergo" -ldflags "$ldflags" \
                -o "$target_dir/$binary_name" ./main.go
        else
            GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=0 \
                go build -trimpath -tags "netgo osusergo" -ldflags "$ldflags" \
                -o "$target_dir/$binary_name" ./main.go
        fi
    )

    cp "$ROOT_DIR/LICENSE" "$ROOT_DIR/README.md" "$ROOT_DIR/screego.config.example" "$target_dir/"

    if [[ "$goos" == "windows" ]]; then
        (
            cd "$target_dir"
            zip -qr "$output_archive.zip" .
        )
    else
        tar -C "$target_dir" -czf "$output_archive.tar.gz" .
    fi
}

for goos in "${GOOS_TARGETS[@]}"; do
    for goarch in "${GOARCH_TARGETS[@]}"; do
        tuple="$goos/$goarch"
        if is_supported "$tuple"; then
            build_target "$goos" "$goarch"
        fi
    done

    if is_supported "$goos/arm"; then
        build_target "$goos" "arm" "6"
        build_target "$goos" "arm" "7"
    fi
done

rm -rf "$TMP_DIR"

echo
echo "Build complete."
echo "Artifacts:"
ls -1 "$DIST_DIR"
