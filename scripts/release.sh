#!/bin/bash
set -euo pipefail

# ============================================================
# NebularNews — Automated Archive + TestFlight Upload
# Usage: ./scripts/release.sh [--build | --patch | --minor]
#   --build  bump only the build number (1.0.1 (12) → 1.0.1 (13))  [default]
#   --patch  bump patch version (1.0.1 → 1.0.2) — Apple App Store review trigger
#   --minor  bump minor version (1.0.1 → 1.1.0) — Apple App Store review trigger
#
# IMPORTANT: marketing-version bumps (--patch / --minor) require a new App Store
# review at app submission time. For TestFlight iteration during development,
# stick with --build (the default). Only use --patch/--minor when you're ready
# to ship a release that the user has explicitly asked for.
#
# Non-interactive auth (for CI/agents):
#   ASC_API_KEY_PATH   — path to .p8 key file
#   ASC_API_KEY_ID     — key ID from App Store Connect
#   ASC_API_ISSUER_ID  — issuer ID from App Store Connect
#
# Beta-group auto-assignment (optional — skips the manual "add my group to
# this build" step in App Store Connect after every upload):
#   ASC_APP_ID            — numeric App Store Connect app id
#   ASC_BETA_GROUP_IDS    — comma-separated beta group ids
# Run `./scripts/asc.rb list-apps` and `./scripts/asc.rb list-groups APP_ID`
# once to discover the values, then export them in your shell profile.
#
# Skip the auto-assign for one run with: SKIP_BETA_ASSIGN=1
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
BUMP_TYPE="build"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --minor) BUMP_TYPE="minor"; shift ;;
    --patch) BUMP_TYPE="patch"; shift ;;
    --build) BUMP_TYPE="build"; shift ;;
    *) fail "Unknown flag: $1. Use --build, --patch, or --minor." ;;
  esac
done

# ============================================================
# 1. Bump version numbers
# ============================================================
step "Bumping version ($BUMP_TYPE)..."
cd "$PROJECT_DIR"

OLD_BUILD=$(agvtool what-version -terse | tail -1)
# Read marketing version from Info.plist — that's the actual source of truth at
# archive time. project.pbxproj's MARKETING_VERSION is stale and unused here.
OLD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Config/NebularNewsApp-Info.plist)

NEW_BUILD=$((OLD_BUILD + 1))
agvtool new-version -all "$NEW_BUILD" > /dev/null

if [ "$BUMP_TYPE" = "build" ]; then
  # Default path: leave the marketing version alone. TestFlight build-only
  # uploads stay under the same App Store record and avoid triggering Apple
  # review.
  NEW_VERSION="$OLD_VERSION"
  echo "  Version: $OLD_VERSION (unchanged) — build $OLD_BUILD → $NEW_BUILD"
else
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
  echo "  Version: $OLD_VERSION → $NEW_VERSION (build $NEW_BUILD) — App Store review trigger"
fi

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
# 6. Assign to beta groups (optional)
# ============================================================
if [ "${SKIP_BETA_ASSIGN:-0}" = "1" ]; then
  echo -e "\n${GREEN}✔ NebularNews $NEW_VERSION ($NEW_BUILD) uploaded to TestFlight${NC}"
  echo "  Beta-group assignment skipped (SKIP_BETA_ASSIGN=1)."
  exit 0
fi

if [ -n "${ASC_APP_ID:-}" ] && [ -n "${ASC_BETA_GROUP_IDS:-}" ]; then
  step "Assigning build to beta groups..."
  export ASC_API_KEY_PATH="$ASC_KEY_PATH"
  export ASC_API_KEY_ID="$ASC_KEY_ID"
  export ASC_API_ISSUER_ID="$ASC_ISSUER"

  if BUILD_ID=$(/usr/bin/ruby "$SCRIPT_DIR/asc.rb" find-build "$ASC_APP_ID" "$NEW_VERSION" "$NEW_BUILD"); then
    /usr/bin/ruby "$SCRIPT_DIR/asc.rb" add-to-groups "$BUILD_ID" "$ASC_BETA_GROUP_IDS" \
      || echo "  ⚠ Beta-group assignment failed — assign manually in App Store Connect."
  else
    echo "  ⚠ Build did not register within the timeout — assign manually in App Store Connect."
  fi
else
  echo -e "\n  ${GREEN}ℹ${NC} Beta-group assignment skipped — set ASC_APP_ID and ASC_BETA_GROUP_IDS to automate."
  echo "    Discover ids: $SCRIPT_DIR/asc.rb list-apps"
  echo "                  $SCRIPT_DIR/asc.rb list-groups <APP_ID>"
fi

# ============================================================
# Done
# ============================================================
echo -e "\n${GREEN}✔ NebularNews $NEW_VERSION ($NEW_BUILD) uploaded to TestFlight${NC}"
echo "  Check App Store Connect for processing status."
