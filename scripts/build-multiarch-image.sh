#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="${DOCKERFILE:-Dockerfile.multiarch}"
BUILDER_NAME="screego-multiarch"
IMAGE_REPO=""
VERSION=""
PLATFORMS="linux/amd64,linux/386,linux/arm64,linux/arm/v7,linux/arm/v6,linux/ppc64le"
PUSH=true
NO_CACHE=false
DRY_RUN=false
OUTPUT_OCI=""
TAGS=()

usage() {
    cat <<'EOF'
Build and optionally push a multi-arch screego image with custom tags.

Usage:
  ./scripts/build-multiarch-image.sh --repo <repo> --tag <tag> [--tag <tag> ...] [options]

Required:
  --repo <repo>        Image repository, e.g. ghcr.io/acme/screego-server
  --tag <tag>          Tag to build/push. Repeat flag for multiple tags.

Options:
  --version <value>    Version embedded into binary (default: git describe --tags --always --dirty).
  --platforms <list>   Comma-separated buildx platforms.
                       Default: linux/amd64,linux/386,linux/arm64,linux/arm/v7,linux/arm/v6,linux/ppc64le
  --builder <name>     Buildx builder name (default: screego-multiarch).
  --no-push            Build without pushing.
                       Single platform: loads image into local Docker daemon.
                       Multi-platform: exports OCI archive locally.
  --output-oci <path>  Custom path for OCI archive when using --no-push with multi-platform
                       builds (default: dist/docker/<repo>_<tag>.oci.tar).
  --no-cache           Disable docker build cache.
  --dry-run            Print command and exit.
  -h, --help           Show this help.

Examples:
  ./scripts/build-multiarch-image.sh \
    --repo ghcr.io/acme/screego-server \
    --tag 1.12.2b \
    --tag latest

  ./scripts/build-multiarch-image.sh \
    --repo ghcr.io/acme/screego-server \
    --tag dev \
    --no-push \
    --platforms linux/amd64

  ./scripts/build-multiarch-image.sh \
    --repo ghcr.io/acme/screego-server \
    --tag dev \
    --no-push \
    --platforms linux/amd64,linux/arm64
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            IMAGE_REPO="${2:-}"
            shift 2
            ;;
        --tag)
            TAGS+=("${2:-}")
            shift 2
            ;;
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --platforms)
            PLATFORMS="${2:-}"
            shift 2
            ;;
        --builder)
            BUILDER_NAME="${2:-}"
            shift 2
            ;;
        --no-push)
            PUSH=false
            shift
            ;;
        --output-oci)
            OUTPUT_OCI="${2:-}"
            shift 2
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
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

require_cmd git
if [[ "$DRY_RUN" == "false" ]]; then
    require_cmd docker
fi

if [[ -z "$IMAGE_REPO" ]]; then
    echo "--repo is required" >&2
    usage
    exit 1
fi

if [[ ${#TAGS[@]} -eq 0 ]]; then
    echo "At least one --tag is required" >&2
    usage
    exit 1
fi

if [[ -z "$VERSION" ]]; then
    VERSION="$(git -C "$ROOT_DIR" describe --tags --always --dirty 2>/dev/null || true)"
    if [[ -z "$VERSION" ]]; then
        VERSION="snapshot"
    fi
fi
VERSION="${VERSION#v}"
COMMIT="$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"

if [[ "$PUSH" == "false" ]]; then
    if [[ -n "$OUTPUT_OCI" && "$PLATFORMS" != *,* ]]; then
        echo "--output-oci is intended for multi-platform builds. For single-platform --no-push, omit --output-oci to use --load." >&2
        exit 1
    fi
fi

if [[ ! -f "$ROOT_DIR/$DOCKERFILE" ]]; then
    echo "Dockerfile not found: $ROOT_DIR/$DOCKERFILE" >&2
    exit 1
fi

if [[ "$DRY_RUN" == "false" ]]; then
    if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
        docker buildx create --name "$BUILDER_NAME" --driver docker-container --use >/dev/null
    else
        docker buildx use "$BUILDER_NAME" >/dev/null
    fi
    docker buildx inspect --bootstrap >/dev/null
fi

cmd=(
    docker buildx build
    --builder "$BUILDER_NAME"
    --platform "$PLATFORMS"
    --build-arg "VERSION=$VERSION"
    --build-arg "COMMIT=$COMMIT"
    -f "$DOCKERFILE"
)

for tag in "${TAGS[@]}"; do
    cmd+=( -t "${IMAGE_REPO}:${tag}" )
done

if [[ "$NO_CACHE" == "true" ]]; then
    cmd+=( --no-cache )
fi

if [[ "$PUSH" == "true" ]]; then
    cmd+=( --push )
else
    if [[ "$PLATFORMS" == *,* ]]; then
        if [[ -z "$OUTPUT_OCI" ]]; then
            safe_repo="${IMAGE_REPO//\//_}"
            safe_repo="${safe_repo//:/_}"
            safe_tag="${TAGS[0]//\//_}"
            safe_tag="${safe_tag//:/_}"
            OUTPUT_OCI="$ROOT_DIR/dist/docker/${safe_repo}_${safe_tag}.oci.tar"
        fi
        mkdir -p "$(dirname "$OUTPUT_OCI")"
        cmd+=( --output "type=oci,dest=${OUTPUT_OCI},tar=true" )
    else
        cmd+=( --load )
    fi
fi

cmd+=( "$ROOT_DIR" )

echo "Repository: $IMAGE_REPO"
echo "Tags: ${TAGS[*]}"
echo "Platforms: $PLATFORMS"
echo "Version: $VERSION"
echo "Commit: $COMMIT"
echo "Dockerfile: $DOCKERFILE"
if [[ "$PUSH" == "false" && -n "$OUTPUT_OCI" ]]; then
    echo "OCI archive: $OUTPUT_OCI"
fi
echo
echo "Running:"
printf ' %q' "${cmd[@]}"
echo

if [[ "$DRY_RUN" == "true" ]]; then
    exit 0
fi

"${cmd[@]}"

echo
echo "Build finished successfully."
if [[ "$PUSH" == "true" ]]; then
    echo "Pushed:"
    for tag in "${TAGS[@]}"; do
        echo "  - ${IMAGE_REPO}:${tag}"
    done
elif [[ -n "$OUTPUT_OCI" ]]; then
    echo "OCI archive written to: $OUTPUT_OCI"
fi
