#!/bin/bash
set -euo pipefail

# ============================================================
# NebularNews — Automated Archive + TestFlight Upload
# Usage: ./scripts/release.sh
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
# 1. Bump version numbers using agvtool
# ============================================================
step "Bumping version..."
cd "$PROJECT_DIR"

# Get current values
OLD_BUILD=$(agvtool what-version -terse)
OLD_VERSION=$(agvtool what-marketing-version -terse1 | head -1 | cut -d= -f2)

# Bump build number
NEW_BUILD=$((OLD_BUILD + 1))
agvtool new-version -all "$NEW_BUILD" > /dev/null

# Bump marketing version (patch: 1.0 → 1.1, or 1.0.3 → 1.0.4)
IFS='.' read -ra PARTS <<< "$OLD_VERSION"
MAJOR="${PARTS[0]:-1}"
MINOR="${PARTS[1]:-0}"
PATCH="${PARTS[2]:-}"

if [ -z "$PATCH" ]; then
  # Two-part version (1.0 → 1.1)
  NEW_MINOR=$((MINOR + 1))
  NEW_VERSION="$MAJOR.$NEW_MINOR"
else
  # Three-part version (1.0.3 → 1.0.4)
  NEW_PATCH=$((PATCH + 1))
  NEW_VERSION="$MAJOR.$MINOR.$NEW_PATCH"
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

EXPORT_OUTPUT=$(xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  2>&1)

echo "$EXPORT_OUTPUT" | grep -E "(Export Succeeded|error:|\*\*)" | head -5

if ! echo "$EXPORT_OUTPUT" | grep -q "EXPORT SUCCEEDED"; then
  fail "Export failed — check signing and App Store Connect credentials"
fi

# ============================================================
# 5. Commit the version bump
# ============================================================
step "Committing version bump..."
cd "$SCRIPT_DIR/.."
git add -A NebularNews/NebularNews.xcodeproj
git commit -m "Release $NEW_VERSION (build $NEW_BUILD) to TestFlight"

# ============================================================
# Done
# ============================================================
echo -e "\n${GREEN}✔ NebularNews $NEW_VERSION ($NEW_BUILD) uploaded to TestFlight${NC}"
echo "  Check App Store Connect for processing status."
