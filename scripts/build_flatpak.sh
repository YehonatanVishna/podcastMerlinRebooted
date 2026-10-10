#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.podcastmerlin.podcast_merlin_flutter"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_ROOT}/build/flatpak"
BUNDLE_DIR="${PROJECT_ROOT}/build/linux/x64/release/bundle"
OUTPUT_BUNDLE="${PROJECT_ROOT}/build/podcast_merlin.flatpak"
MANIFEST="${PROJECT_ROOT}/com.podcastmerlin.podcast_merlin_flutter.yaml"

INSTALL_FLAG=false
SKIP_FLUTTER=false
CLEAN_FLAG=false

for arg in "$@"; do
  case "$arg" in
    --install)
      INSTALL_FLAG=true
      ;;
    --skip-flutter)
      SKIP_FLUTTER=true
      ;;
    --clean)
      CLEAN_FLAG=true
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --install       Install the generated Flatpak bundle to the current user"
      echo "  --skip-flutter  Skip 'flutter build linux --release' step"
      echo "  --clean         Remove previous Flatpak build directories before building"
      echo "  --help, -h      Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      exit 1
      ;;
  esac
done

if ! command -v flatpak >/dev/null 2>&1; then
  echo "Error: 'flatpak' is not installed or not in PATH."
  exit 1
fi

if [ "$CLEAN_FLAG" = true ]; then
  echo "==> Cleaning previous Flatpak build artifacts..."
  rm -rf "${BUILD_DIR}" "${OUTPUT_BUNDLE}"
fi

# Step 1: Build Flutter release bundle if needed
if [ "$SKIP_FLUTTER" = false ] || [ ! -d "${BUNDLE_DIR}" ]; then
  echo "==> Building Flutter Linux release bundle..."
  (cd "${PROJECT_ROOT}" && flutter build linux --release)
fi

if [ ! -f "${BUNDLE_DIR}/podcast_merlin_flutter" ]; then
  echo "Error: Release bundle binary not found at ${BUNDLE_DIR}/podcast_merlin_flutter"
  exit 1
fi

# Step 2: Determine build method (flatpak-builder or flatpak run org.flatpak.Builder or flatpak build-init fallback)
REPO_DIR="${BUILD_DIR}/repo"
mkdir -p "${BUILD_DIR}" "${REPO_DIR}"

BUILDER_CMD=()
if command -v flatpak-builder >/dev/null 2>&1; then
  BUILDER_CMD=(flatpak-builder --disable-rofiles-fuse)
elif flatpak info org.flatpak.Builder >/dev/null 2>&1; then
  BUILDER_CMD=(flatpak run org.flatpak.Builder --disable-rofiles-fuse)
fi

if [ ${#BUILDER_CMD[@]} -gt 0 ] && [ -f "${MANIFEST}" ]; then
  echo "==> Building Flatpak with flatpak-builder (${BUILDER_CMD[*]})..."
  "${BUILDER_CMD[@]}" --force-clean --repo="${REPO_DIR}" "${BUILD_DIR}/build-dir" "${MANIFEST}"
else
  echo "Error: 'flatpak-builder' (or 'org.flatpak.Builder') is required to build the Flatpak."
  echo "Podcast Merlin requires libmpv and dependencies to be compiled into the Flatpak sandbox."
  echo "Please install flatpak-builder via your system package manager (e.g. 'sudo dnf install flatpak-builder' or 'sudo apt install flatpak-builder') or run: 'flatpak install flathub org.flatpak.Builder'"
  exit 1
fi

# Step 3: Package repo into standalone .flatpak single-file bundle
echo "==> Creating standalone Flatpak bundle: ${OUTPUT_BUNDLE}..."
mkdir -p "$(dirname "${OUTPUT_BUNDLE}")"
flatpak build-bundle "${REPO_DIR}" "${OUTPUT_BUNDLE}" "${APP_ID}"

echo "==> Flatpak bundle compiled successfully:"
ls -lh "${OUTPUT_BUNDLE}"

if [ "$INSTALL_FLAG" = true ]; then
  echo "==> Installing ${APP_ID} to current user..."
  flatpak install --user --bundle -y "${OUTPUT_BUNDLE}"
  echo "==> Successfully installed! You can run it with: flatpak run ${APP_ID}"
fi
