#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# set_version.sh - Updates version strings across all relevant project files
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat << 'EOF'
Usage:
  ./scripts/set_version.sh [OPTIONS] <VERSION> [BUILD_NUMBER]

Arguments:
  <VERSION>        Semantic version in format X.Y.Z (e.g., 0.2.0 or 0.2.0+2)
  [BUILD_NUMBER]   Optional build number integer (e.g., 2)

Options:
  -b, --build-number <num>  Explicitly specify build number
  --skip-pub-get            Do not run 'flutter pub get' after updating files
  -d, --dry-run             Show planned changes without writing to files
  -h, --help                Show this help message

Examples:
  ./scripts/set_version.sh 0.2.0
  ./scripts/set_version.sh 0.2.0 2
  ./scripts/set_version.sh 0.2.0+2
  ./scripts/set_version.sh --build-number 5 1.0.0
EOF
  exit 0
}

TARGET_VERSION=""
TARGET_BUILD=""
SKIP_PUB_GET=false
DRY_RUN=false

# Parse options
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -b|--build-number)
      TARGET_BUILD="$2"
      shift 2
      ;;
    --skip-pub-get)
      SKIP_PUB_GET=true
      shift
      ;;
    -d|--dry-run)
      DRY_RUN=true
      shift
      ;;
    -*)
      echo "Error: Unknown option '$1'" >&2
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL_ARGS[@]} -eq 0 ]]; then
  echo "Error: Missing required <VERSION> argument." >&2
  usage
fi

TARGET_VERSION="${POSITIONAL_ARGS[0]}"
if [[ ${#POSITIONAL_ARGS[@]} -ge 2 && -z "$TARGET_BUILD" ]]; then
  TARGET_BUILD="${POSITIONAL_ARGS[1]}"
fi

# Split version if passed as X.Y.Z+BUILD
if [[ "$TARGET_VERSION" == *"+"* ]]; then
  PARSED_VERSION="${TARGET_VERSION%%+*}"
  PARSED_BUILD="${TARGET_VERSION#*+}"
  TARGET_VERSION="$PARSED_VERSION"
  if [[ -z "$TARGET_BUILD" ]]; then
    TARGET_BUILD="$PARSED_BUILD"
  fi
fi

# Validate semver format (X.Y.Z)
if [[ ! "$TARGET_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Error: Version '$TARGET_VERSION' does not match semantic versioning format X.Y.Z (e.g. 0.1.0)" >&2
  exit 1
fi

MAJOR="${BASH_REMATCH[1]}"
MINOR="${BASH_REMATCH[2]}"
PATCH="${BASH_REMATCH[3]}"

# If build number was not specified, extract existing from pubspec.yaml or default to 1
PUBSPEC_FILE="${PROJECT_ROOT}/pubspec.yaml"
if [[ -z "$TARGET_BUILD" ]]; then
  if [[ -f "$PUBSPEC_FILE" ]]; then
    EXISTING_BUILD="$(grep -E '^version:[[:space:]]*[0-9.]+\+[0-9]+' "$PUBSPEC_FILE" | sed -E 's/.*[0-9.]+\+([0-9]+)/\1/' || true)"
    if [[ -n "$EXISTING_BUILD" ]]; then
      TARGET_BUILD="$EXISTING_BUILD"
    else
      TARGET_BUILD="1"
    fi
  else
    TARGET_BUILD="1"
  fi
fi

if [[ ! "$TARGET_BUILD" =~ ^[0-9]+$ ]]; then
  echo "Error: Build number '$TARGET_BUILD' must be an integer." >&2
  exit 1
fi

SEMVER="$TARGET_VERSION"
BUILD_NUM="$TARGET_BUILD"
FULL_FLUTTER_VERSION="${SEMVER}+${BUILD_NUM}"
MSIX_VERSION="${MAJOR}.${MINOR}.${PATCH}.0"
RC_VERSION_NUMBER="${MAJOR},${MINOR},${PATCH},${BUILD_NUM}"
RELEASE_DATE="$(date +%Y-%m-%d)"

echo "==> Setting project version:"
echo "    SemVer:         ${SEMVER}"
echo "    Build Number:   ${BUILD_NUM}"
echo "    Flutter Full:   ${FULL_FLUTTER_VERSION}"
echo "    MSIX Version:   ${MSIX_VERSION}"
echo "    Release Date:   ${RELEASE_DATE}"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  echo "[DRY RUN] No files will be modified."
fi

# 1. pubspec.yaml
if [[ -f "$PUBSPEC_FILE" ]]; then
  echo "--> Updating pubspec.yaml..."
  if [[ "$DRY_RUN" == false ]]; then
    python3 -c "
import re, sys

file_path = sys.argv[1]
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace version: X.Y.Z+N
content = re.sub(r'^(version:\s*)[^\s]+', rf'\g<1>${FULL_FLUTTER_VERSION}', content, flags=re.MULTILINE)

# Replace msix_version: X.Y.Z.W
content = re.sub(r'^(\s*msix_version:\s*)[^\s]+', rf'\g<1>${MSIX_VERSION}', content, flags=re.MULTILINE)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
" "$PUBSPEC_FILE"
  fi
fi

# 2. linux/com.podcastmerlin.podcast_merlin_flutter.metainfo.xml
METAINFO_FILE="${PROJECT_ROOT}/linux/com.podcastmerlin.podcast_merlin_flutter.metainfo.xml"
if [[ -f "$METAINFO_FILE" ]]; then
  echo "--> Updating AppStream metainfo.xml..."
  if [[ "$DRY_RUN" == false ]]; then
    python3 -c "
import re, sys

file_path = sys.argv[1]
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the release version and date in metainfo
content = re.sub(
    r'<release\s+version=\"[^\"]*\"\s+date=\"[^\"]*\"',
    f'<release version=\"${SEMVER}\" date=\"${RELEASE_DATE}\"',
    content,
    count=1
)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
" "$METAINFO_FILE"
  fi
fi

# 3. windows/runner/Runner.rc
RUNNER_RC_FILE="${PROJECT_ROOT}/windows/runner/Runner.rc"
if [[ -f "$RUNNER_RC_FILE" ]]; then
  echo "--> Updating Windows Runner.rc..."
  if [[ "$DRY_RUN" == false ]]; then
    python3 -c "
import re, sys

file_path = sys.argv[1]
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace fallback VERSION_AS_NUMBER
content = re.sub(
    r'(#define\s+VERSION_AS_NUMBER\s+)[0-9,]+',
    rf'\g<1>${RC_VERSION_NUMBER}',
    content
)

# Replace fallback VERSION_AS_STRING
content = re.sub(
    r'(#define\s+VERSION_AS_STRING\s+)\"[^\"]*\"',
    rf'\g<1>\"${SEMVER}\"',
    content
)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
" "$RUNNER_RC_FILE"
  fi
fi

# 4. android/local.properties (if exists)
LOCAL_PROPERTIES_FILE="${PROJECT_ROOT}/android/local.properties"
if [[ -f "$LOCAL_PROPERTIES_FILE" ]]; then
  echo "--> Updating android/local.properties..."
  if [[ "$DRY_RUN" == false ]]; then
    python3 -c "
import re, sys

file_path = sys.argv[1]
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = re.sub(r'^(flutter\.versionName=).*$', rf'\g<1>${SEMVER}', content, flags=re.MULTILINE)
content = re.sub(r'^(flutter\.versionCode=).*$', rf'\g<1>${BUILD_NUM}', content, flags=re.MULTILINE)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
" "$LOCAL_PROPERTIES_FILE"
  fi
fi

# 5. docs/SYSTEM_DEPENDENCIES.md (if exists)
DOC_FILE="${PROJECT_ROOT}/docs/SYSTEM_DEPENDENCIES.md"
if [[ -f "$DOC_FILE" ]]; then
  echo "--> Updating packaging manifests in docs/SYSTEM_DEPENDENCIES.md..."
  if [[ "$DRY_RUN" == false ]]; then
    python3 -c "
import re, sys

file_path = sys.argv[1]
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# RPM spec Version:
content = re.sub(r'^(Version:\s*)[0-9.]+', rf'\g<1>${SEMVER}', content, flags=re.MULTILINE)

# Snapcraft version: 'X.Y.Z'
content = re.sub(r'^(version:\s*)[0-9.\'\"]+', rf\"\g<1>'${SEMVER}'\", content, flags=re.MULTILINE)

# MSIX msix_version:
content = re.sub(r'^(\s*msix_version:\s*)[0-9.]+', rf'\g<1>${MSIX_VERSION}', content, flags=re.MULTILINE)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
" "$DOC_FILE"
  fi
fi

# 6. macos/Runner.xcodeproj/project.pbxproj (if exists)
PBXPROJ_FILE="${PROJECT_ROOT}/macos/Runner.xcodeproj/project.pbxproj"
if [[ -f "$PBXPROJ_FILE" ]]; then
  echo "--> Updating macOS Xcode project.pbxproj..."
  if [[ "$DRY_RUN" == false ]]; then
    python3 -c "
import re, sys

file_path = sys.argv[1]
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace MARKETING_VERSION
content = re.sub(
    r'(MARKETING_VERSION\s*=\s*)[0-9.]+;',
    rf'\g<1>${SEMVER};',
    content
)

# Replace CURRENT_PROJECT_VERSION
content = re.sub(
    r'(CURRENT_PROJECT_VERSION\s*=\s*)[0-9]+;',
    rf'\g<1>${BUILD_NUM};',
    content
)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
" "$PBXPROJ_FILE"
  fi
fi

# 7. macos/Flutter/ephemeral/ config files (if exist)
for mac_eph in "${PROJECT_ROOT}/macos/Flutter/ephemeral/Flutter-Generated.xcconfig" \
              "${PROJECT_ROOT}/macos/Flutter/ephemeral/flutter_native_integration.env"; do
  if [[ -f "$mac_eph" ]]; then
    echo "--> Updating $(basename "$mac_eph")..."
    if [[ "$DRY_RUN" == false ]]; then
      sed -i -E "s/^(FLUTTER_BUILD_NAME=).*/\1${SEMVER}/" "$mac_eph"
      sed -i -E "s/^(FLUTTER_BUILD_NUMBER=).*/\1${BUILD_NUM}/" "$mac_eph"
    fi
  fi
done

MAC_EXPORT_ENV="${PROJECT_ROOT}/macos/Flutter/ephemeral/flutter_export_environment.sh"
if [[ -f "$MAC_EXPORT_ENV" ]]; then
  echo "--> Updating flutter_export_environment.sh..."
  if [[ "$DRY_RUN" == false ]]; then
    sed -i -E "s/^(export \"FLUTTER_BUILD_NAME=).*/\1${SEMVER}\"/" "$MAC_EXPORT_ENV"
    sed -i -E "s/^(export \"FLUTTER_BUILD_NUMBER=).*/\1${BUILD_NUM}\"/" "$MAC_EXPORT_ENV"
  fi
fi

# 8. linux/flutter/ephemeral/generated_config.cmake (if exists)
LINUX_EPH_CMAKE="${PROJECT_ROOT}/linux/flutter/ephemeral/generated_config.cmake"
if [[ -f "$LINUX_EPH_CMAKE" ]]; then
  echo "--> Updating linux generated_config.cmake..."
  if [[ "$DRY_RUN" == false ]]; then
    python3 -c "
import re, sys

file_path = sys.argv[1]
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = re.sub(r'^(set\(FLUTTER_VERSION\s+\")[^\"]+', rf'\g<1>${FULL_FLUTTER_VERSION}', content, flags=re.MULTILINE)
content = re.sub(r'^(set\(FLUTTER_VERSION_MAJOR\s+)[0-9]+', rf'\g<1>${MAJOR}', content, flags=re.MULTILINE)
content = re.sub(r'^(set\(FLUTTER_VERSION_MINOR\s+)[0-9]+', rf'\g<1>${MINOR}', content, flags=re.MULTILINE)
content = re.sub(r'^(set\(FLUTTER_VERSION_PATCH\s+)[0-9]+', rf'\g<1>${PATCH}', content, flags=re.MULTILINE)
content = re.sub(r'^(set\(FLUTTER_VERSION_BUILD\s+)[0-9]+', rf'\g<1>${BUILD_NUM}', content, flags=re.MULTILINE)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
" "$LINUX_EPH_CMAKE"
  fi
fi

# 9. flutter pub get (if not skipped and flutter command available)
if [[ "$SKIP_PUB_GET" == false && "$DRY_RUN" == false ]]; then
  if command -v flutter >/dev/null 2>&1; then
    echo "--> Running 'flutter pub get'..."
    (cd "$PROJECT_ROOT" && flutter pub get)
  fi
fi

echo ""
echo "==> Done! Project version set to ${FULL_FLUTTER_VERSION}."
