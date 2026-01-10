#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/build_release.sh --base-url <url> [--no-bump]

Creates a distributable tar.zst archive for the Ground Markers plugin and writes
dist/meta.json containing the checksum, version, and download URL that Bolt Launcher
expects.

Options:
  --base-url <url>   Base URL where you will host the tarball (required).
  --no-bump          Do not bump bolt.json version; reuse the existing value.
  --tar-only         Only create the tar.zst archive; skip checksum/meta output.
EOF
}

BASE_URL=""
NO_BUMP=false
TAR_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url)
            BASE_URL="${2:-}"
            shift 2
            ;;
        --no-bump)
            NO_BUMP=true
            shift
            ;;
        --tar-only)
            TAR_ONLY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$BASE_URL" && "$TAR_ONLY" == false ]]; then
    echo "Error: --base-url is required unless --tar-only is specified." >&2
    usage
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

required_entries=(
    bolt.json
    LICENSE
    main.lua
    core
    data
    gfx
    input
    ui
)

missing=()
for entry in "${required_entries[@]}"; do
    if [[ ! -e "$entry" ]]; then
        missing+=("$entry")
    fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: missing required files/directories: ${missing[*]}" >&2
    exit 1
fi

current_version="$(grep -Po '"version":\s*"\K[^"]+' bolt.json || true)"
if [[ -z "$current_version" ]]; then
    echo "Error: could not read version from bolt.json." >&2
    exit 1
fi

bump_version() {
    local version="$1"
    local IFS='.'
    read -r -a parts <<<"$version"
    local last_index=$(( ${#parts[@]} - 1 ))
    if ! [[ "${parts[$last_index]}" =~ ^[0-9]+$ ]]; then
        echo "Error: cannot bump version '$version'; last segment must be numeric." >&2
        exit 1
    fi
    parts[$last_index]=$(( parts[$last_index] + 1 ))
    (IFS='.'; echo "${parts[*]}")
}

if [[ "$NO_BUMP" == false ]]; then
    new_version="$(bump_version "$current_version")"
    perl -0pi -e "s/\"version\":\\s*\"[^\"]*\"/\"version\": \"$new_version\"/" bolt.json
    echo "Bumped version: $current_version -> $new_version"
else
    new_version="$current_version"
    echo "Packaging existing version: $new_version"
fi

DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$DIST_DIR"

# Remove existing tarballs to keep dist directory clean
echo "Cleaning up old tarballs from $DIST_DIR..."
rm -f "$DIST_DIR"/*.tar.zst "$DIST_DIR"/*.tar

artifact_name="bolt-groundmarkers-v${new_version}"
tar_path="$DIST_DIR/${artifact_name}.tar"

tar -cf "$tar_path" "${required_entries[@]}"

if ! command -v zstd >/dev/null 2>&1; then
    echo "Error: zstd is required but not found in PATH." >&2
    exit 1
fi

zstd -T0 --rm -f "$tar_path"
archive_path="${tar_path}.zst"

if [[ "$TAR_ONLY" == true ]]; then
    echo "Created archive: $archive_path"
    echo "Tar-only mode enabled; skipping checksum and meta.json generation."
    exit 0
fi

if ! command -v sha256sum >/dev/null 2>&1; then
    echo "Error: sha256sum is required but not found in PATH." >&2
    exit 1
fi

checksum="$(sha256sum "$archive_path" | awk '{print $1}')"

base_url_trimmed="${BASE_URL%/}"
download_url="${base_url_trimmed}/$(basename "$archive_path")"

cat > "$DIST_DIR/meta.json" <<EOF
{
  "sha256": "$checksum",
  "version": "$new_version",
  "url": "$download_url"
}
EOF

echo "Created archive: $archive_path"
echo "SHA256: $checksum"
echo "Meta file: $DIST_DIR/meta.json"
echo "Done."
