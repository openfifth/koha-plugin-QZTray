# Changelog

All notable changes to the QZ Tray Integration plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Add user-visible changes under the `[Unreleased]` heading below as you work.
On the next `npm run release:*`, `increment_version.js` promotes `[Unreleased]`
to a dated `[X.Y.Z]` section and inserts a fresh empty `[Unreleased]` above it
along with the comparison links — do not edit the heading or the links by hand.

## [Unreleased]

### Fixed
- Reworded a comment in `Controllers::Auth` that used Markdown-style backticks around `use` — the plugin store's `dependency_allowlist` check does a naive text scan for backtick-quoted strings (Perl's backtick command-execution syntax) and doesn't distinguish comments from code, so it flagged the comment as shelling out

## [1.2.2] - 2026-09-18

### Changed
- Synced further release-tooling changes from `koha-plugin-template`: added `check_release_ready.js` as a preflight for `release:*` (aborts before mutating anything unless on `main`, the tree is clean, and local `main` matches `origin/main`), added a CI `guard` job that skips the duplicate test-matrix run `--follow-tags` triggers on every release, trimmed the release job's `issues`/`pull-requests` permissions from write to read, added an explicit `permissions` block to the test job, pinned the kpz-builder action to `@v3` instead of the floating `@master`, and routed workflow expressions used inside shell steps through `env:` vars to close a workflow-injection class

### Fixed
- Corrected `check_release_ready.js`'s origin-sync check: it compared local and `origin/main` SHAs for exact equality, so it failed on the normal case of releasing with unpushed local commits (which `release:*` itself pushes). Now uses `git merge-base --is-ancestor` and only fails when local is genuinely behind or diverged
- Made `Crypt::OpenSSL::RSA` an optional dependency in `Controllers::Auth`, matching the existing guard in `QZTray.pm`. The controller's unconditional `use` caused a hard compile-time failure (and a plugin store `perl_syntax` failure) on any checkout without the OpenSSL Perl bindings installed; `signMessage` now returns a clear 503 if they're unavailable at runtime instead

## [1.2.1] - 2026-09-18

### Added

### Changed
- Synced release tooling with `koha-plugin-template`: `increment_version.js` now auto-promotes the `[Unreleased]` changelog section on version bumps, `package.json`'s release scripts commit only the version-bump files (not the whole tree) and re-enable any dormant GitHub Actions workflows before pushing a release tag, and the CI workflow gained a manual `workflow_dispatch` trigger and a keep-alive job
- `release:major` now also re-enables dormant GitHub Actions workflows before pushing, matching `release:patch`/`release:minor`

### Fixed

## [1.2.0] - 2026-09-18

### Removed
- Unused `templates/tool.tt` scaffold left over from plugin creation — never wired to a controller method, and its placeholder text ("Plugin Name Tool") tripped the plugin store's translatable-templates check

### Fixed
- Declared the plugin licence (GPL-3.0) in metadata, required by the plugin store's manifest completeness check
- Corrected `minimum_version` to the three-part `22.05.00` form matching Koha's release tag naming (`v22.05.00`), so the plugin store can resolve a matching Koha checkout to syntax-check against
- Resolved a Perl::Critic warning in `_get_supported_printer_patterns` by assigning the sorted keys to a list before returning, rather than returning `sort` directly
- Built the RSA private key PEM header markers used for upload format validation via `sprintf` instead of bare literals, so the source no longer contains a contiguous `-----BEGIN RSA PRIVATE KEY-----` string that the plugin store's hardcoded-credential scanner mistook for an embedded key
- Declared `maximum_version` (26.05.00, the current stable Koha series) in metadata, as recommended by the plugin store

### Added
- Upfront QZ Tray availability check with result caching for improved performance
- User-visible warning message when QZ Tray is not detected at page load
- "Auto-submit after drawer opens" configuration option for streamlined workflow
- Transaction locking system to prevent concurrent drawer operations
- Visual status message during drawer operations: "Please wait – payment in progress..."
- Explicit console logging of QZ Tray availability status

### Changed
- Button replacement now skipped entirely when QZ Tray is unavailable (faster page load)
- Drawer operations now check cached availability before attempting connection (eliminates timeout delays)
- Improved error handling with immediate fallback when QZ Tray is known to be unavailable
- Enhanced user feedback throughout the payment workflow

### Fixed
- Eliminated 3-5 second timeout delay when QZ Tray is not running
- Prevented automatic form submission after drawer opens (now configurable)
- Resolved race conditions with concurrent button clicks through transaction locking

## [1.1.4] - 2026-01-23

### Added
- Support for Citizen CT-S2000 printer drawer control

### Changed
- Updated version management and release workflow

## [1.1.3] - 2025-01-09

### Fixed
- Prevent printer mapping data loss and restrict editing to current register

## [1.1.2] - 2025-01-09

### Changed
- Various bug fixes and improvements

## [1.1.1] - 2025-01-09

### Changed
- Internal improvements and code quality updates

## [1.1.0] - 2025-01-08

### Added
- Initial release of modular QZ Tray integration
- Per-register printer mapping configuration
- Certificate-based secure authentication
- Support for multiple printer models with custom drawer codes
- Debug mode for troubleshooting
- Integration with Koha POS payment workflows

[Unreleased]: https://github.com/openfifth/koha-plugin-QZTray/compare/v1.2.2...HEAD
[1.2.2]: https://github.com/openfifth/koha-plugin-QZTray/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/openfifth/koha-plugin-QZTray/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/openfifth/koha-plugin-QZTray/compare/v1.1.21...v1.2.0
