# Changelog

All notable changes to the QZ Tray Integration plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
