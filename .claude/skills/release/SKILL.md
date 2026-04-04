---
name: release
description: Archive and upload NebularNews to TestFlight with pre-flight checks
user-invocable: true
disable-model-invocation: true
---

# Release to TestFlight

Run pre-flight checks, then execute the release script to archive and upload to TestFlight.

## Pre-flight Checks

Before running the release script, verify:

1. **Clean working tree**: Run `git status` — there should be no uncommitted changes. If there are, ask the user whether to commit or stash them first.

2. **Build passes**: Run:
   ```bash
   xcodebuild -project NebularNews/NebularNews.xcodeproj -scheme NebularNews -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
   ```
   If the build fails, stop and report the error. Do not proceed.

3. **Current version**: Run `cd NebularNews && agvtool what-marketing-version -terse1 && agvtool what-version -terse` to show the current version and build number. Tell the user what the next version will be.

4. **Confirm**: Ask the user to confirm before proceeding.

## Release

Run the release script:
```bash
./scripts/release.sh
```

The script handles: version bump → SPM resolve → archive → export → upload → commit.

## Post-flight

After a successful release:

1. Update `.docs/ai/current-state.md` with the new build number and version.
2. Tell the user to check App Store Connect for processing status.
3. If the release failed, report the exact error from the script output.
