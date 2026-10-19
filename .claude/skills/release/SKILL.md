---
name: release
description: Build Slash.app and publish a new GitHub Release (which the installed app then auto-updates to). Use when asked to release, publish, ship or bump the version of Slash.
---

# Releasing Slash

Releases are fully automated by `.github/workflows/release.yml`:

1. Any push to `main` (or a `claude/**` branch) that touches code runs the workflow on a macOS runner.
2. It builds a universal `Slash.app` with `scripts/build-app.sh <version>` (icon from `Resources/AppIcon.png`, ad-hoc signed) and zips it as `Slash.zip`.
3. It publishes a GitHub Release tagged `v<MAJOR.MINOR>.<run_number>` with `Slash.zip` attached.
4. Installed copies of Slash check `releases/latest` at launch and every 6 hours (`Sources/Slash/Updater.swift`), download `Slash.zip`, swap the bundle and relaunch.

## To release
- Commit and push to `main`. Done.
- For a minor/major bump, edit the `VERSION` file (e.g. `1.1`) before pushing.
- To re-run without a code change: Actions tab → "Build & Release" → Run workflow.

## Rules
- The release asset must stay named `*.zip` and contain `Slash.app` at its root (the updater relies on it).
- Never change `Updater.repo` without also moving the releases.
- After pushing, check the workflow run; if the Swift build fails, fix the compile error and push again.
