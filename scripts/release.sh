#!/bin/bash
set -euo pipefail

# ============================================================
# NebularNews — Automated Archive + TestFlight Upload
# Usage: ./scripts/release.sh [--minor | --patch]
#   --patch  bump patch version (2.0.1 → 2.0.2)  [default]
#   --minor  bump minor version (2.0.1 → 2.1.0)
#
# Non-interactive auth (for CI/agents):
#   ASC_API_KEY_PATH   — path to .p8 key file
#   ASC_API_KEY_ID     — key ID from App Store Connect
#   ASC_API_ISSUER_ID  — issuer ID from App Store Connect
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../NebularNews"
BUILD_DIR="$SCRIPT_DIR/../build"
ARCHIVE_PATH="$BUILD_DIR/NebularNews.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

step() { echo -e "\n${GREEN}▸ $1${NC}"; }
fail() { echo -e "${RED}✘ $1${NC}"; exit 1; }

# ============================================================
# Parse flags
# ============================================================
BUMP_TYPE="patch"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --minor) BUMP_TYPE="minor"; shift ;;
    --patch) BUMP_TYPE="patch"; shift ;;
    *) fail "Unknown flag: $1. Use --patch or --minor." ;;
  esac
done

# ============================================================
# 1. Bump version numbers
# ============================================================
step "Bumping version ($BUMP_TYPE)..."
cd "$PROJECT_DIR"

OLD_BUILD=$(agvtool what-version -terse | tail -1)
# Read MARKETING_VERSION directly from project.pbxproj (agvtool can't resolve it without Info.plist)
OLD_VERSION=$(grep -m1 'MARKETING_VERSION = ' NebularNews.xcodeproj/project.pbxproj | sed 's/.*= //;s/;.*//' | tr -d '[:space:]')

NEW_BUILD=$((OLD_BUILD + 1))
agvtool new-version -all "$NEW_BUILD" > /dev/null

IFS='.' read -ra PARTS <<< "$OLD_VERSION"
MAJOR="${PARTS[0]:-2}"
MINOR="${PARTS[1]:-0}"
PATCH="${PARTS[2]:-0}"

if [ "$BUMP_TYPE" = "minor" ]; then
  NEW_VERSION="$MAJOR.$((MINOR + 1)).0"
else
  NEW_VERSION="$MAJOR.$MINOR.$((PATCH + 1))"
fi

agvtool new-marketing-version "$NEW_VERSION" > /dev/null

echo "  Version: $OLD_VERSION → $NEW_VERSION (build $NEW_BUILD)"

# ============================================================
# 2. Resolve SPM packages
# ============================================================
step "Resolving packages..."
xcodebuild -resolvePackageDependencies \
  -project NebularNews.xcodeproj \
  -scheme NebularNews \
  -clonedSourcePackagesDirPath "$BUILD_DIR/spm" \
  2>&1 | tail -3

# ============================================================
# 3. Archive
# ============================================================
step "Archiving NebularNews $NEW_VERSION ($NEW_BUILD)..."
rm -rf "$ARCHIVE_PATH"

xcodebuild archive \
  -project NebularNews.xcodeproj \
  -scheme NebularNews \
  -archivePath "$ARCHIVE_PATH" \
  -clonedSourcePackagesDirPath "$BUILD_DIR/spm" \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM=K7CBQW6MPG \
  2>&1 | grep -E "(Archive Succeeded|error:|\*\*)" | head -5

if [ ! -d "$ARCHIVE_PATH" ]; then
  fail "Archive failed — $ARCHIVE_PATH not created"
fi

echo "  Archive: $ARCHIVE_PATH"

# ============================================================
# 4. Export + Upload to App Store Connect
# ============================================================
step "Exporting and uploading to TestFlight..."
rm -rf "$EXPORT_PATH"

EXPORT_CMD=(
  xcodebuild -exportArchive
  -archivePath "$ARCHIVE_PATH"
  -exportOptionsPlist "$EXPORT_OPTIONS"
  -exportPath "$EXPORT_PATH"
  -allowProvisioningUpdates
)

ASC_KEY_PATH="${ASC_API_KEY_PATH:-$HOME/.appstoreconnect/AuthKey_J79935N6P6.p8}"
ASC_KEY_ID="${ASC_API_KEY_ID:-J79935N6P6}"
ASC_ISSUER="${ASC_API_ISSUER_ID:-fe27785a-1413-46ff-bd82-111de0da024f}"

if [ -f "$ASC_KEY_PATH" ]; then
  echo "  Using App Store Connect API Key for auth"
  EXPORT_CMD+=(
    -authenticationKeyPath "$ASC_KEY_PATH"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER"
  )
else
  echo "  Warning: API key not found at $ASC_KEY_PATH — falling back to Xcode session auth"
fi

EXPORT_OUTPUT=$("${EXPORT_CMD[@]}" 2>&1)

echo "$EXPORT_OUTPUT" | grep -E "(Export Succeeded|error:|\*\*)" | head -5

if ! echo "$EXPORT_OUTPUT" | grep -q "EXPORT SUCCEEDED"; then
  fail "Export failed — check signing and App Store Connect credentials"
fi

# ============================================================
# 5. Commit the version bump
# ============================================================
step "Committing version bump..."
cd "$SCRIPT_DIR/.."
git add -A NebularNews/NebularNews.xcodeproj NebularNews/Config/NebularNewsApp-Info.plist
git commit -m "Release $NEW_VERSION (build $NEW_BUILD) to TestFlight"

# ============================================================
# Done
# ============================================================
echo -e "\n${GREEN}✔ NebularNews $NEW_VERSION ($NEW_BUILD) uploaded to TestFlight${NC}"
echo "  Check App Store Connect for processing status."
