# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Koha plugin that integrates QZ Tray printing functionality for cash drawer operations in library management workflows. The plugin enables secure communication with QZ Tray for opening cash drawers during payment processing, refunds, and other monetary transactions.

## Repository Structure

The project follows the standard Koha plugin structure:
- `Koha/Plugin/Com/OpenFifth/QZTray.pm` - Main plugin module with core functionality
- `Koha/Plugin/Com/OpenFifth/QZTray/Controllers/Auth.pm` - API controller for certificate management and message signing
- `Koha/Plugin/Com/OpenFifth/QZTray/templates/` - Template Toolkit files for configuration UI
- `Koha/Plugin/Com/OpenFifth/QZTray/js/` - JavaScript libraries (QZ Tray dependencies)
- `Koha/Plugin/Com/OpenFifth/QZTray/api/` - OpenAPI specifications for REST endpoints

## Development Commands

### Version Management
- `npm run version:patch` - Increment patch version and update plugin files
- `npm run version:minor` - Increment minor version and update plugin files
- `npm run version:major` - Increment major version and update plugin files

### Release Management
- `npm run release:patch` - Bump patch version, commit, tag, and push
- `npm run release:minor` - Bump minor version, commit, tag, and push
- `npm run release:major` - Bump major version, commit, tag, and push

The version management system automatically:
1. Updates version in `package.json`
2. Updates `$VERSION` variable in main plugin file (QZTray.pm:11)
3. Updates `date_updated` field in plugin metadata (QZTray.pm:19)
4. Commits changes with standardized message
5. Creates git tag with version number
6. Pushes changes and tags to remote

## Plugin Architecture

### Core Components

1. **Main Plugin Module** (`QZTray.pm`)
   - Extends `Koha::Plugins::Base`
   - Handles plugin lifecycle (install/upgrade/uninstall)
   - Provides configuration interface
   - Generates JavaScript for staff interface integration
   - Manages certificate and private key storage

2. **Authentication Controller** (`Controllers/Auth.pm`)
   - REST API endpoints for QZ Tray authentication
   - Certificate retrieval endpoint (`/api/v1/contrib/qztray/certificate`)
   - Message signing endpoint (`/api/v1/contrib/qztray/sign`)
   - Uses Crypt::OpenSSL::RSA for RSA signing with SHA1

3. **JavaScript Integration**
   - Injected into staff interface via `intranet_js()` method
   - Handles QZ Tray connection and cash drawer operations
   - Automatically replaces payment/transaction buttons on specific pages
   - Supports multiple printer types with custom drawer codes

### Key Features

- **Secure Certificate Management**: Stores digital certificates and private keys in plugin data
- **Cash Drawer Integration**: Opens cash drawers on payment confirmations, refunds, and cashups
- **Multi-Printer Support**: Configurable printer selection with different drawer codes for various printer models
- **Page-Specific Button Integration**: Automatically enhances UI on payment pages (POS, member payments, etc.)
- **Duplicate Prevention**: Prevents multiple simultaneous drawer operations

### Configuration

The plugin requires:
1. Digital certificate file (PEM format) for QZ Tray authentication
2. Private key file for message signing
3. Optional preferred printer selection

Configuration is handled through the plugin's configure method, accessible via Koha's plugin management interface.

### API Endpoints

- `GET /api/v1/contrib/qztray/certificate` - Retrieve stored certificate
- `POST /api/v1/contrib/qztray/sign` - Sign messages for QZ Tray authentication
- Static file serving for JavaScript dependencies

### JavaScript Dependencies

The plugin includes required QZ Tray libraries:
- `rsvp-3.1.0.min.js` - Promise library
- `sha-256.min.js` - SHA-256 hashing
- `jsrsasign-all-min.js` - RSA signing for JavaScript
- `qz-tray.js` - QZ Tray API client

### Supported Payment Pages

The plugin automatically integrates with these Koha pages:
- POS payment confirmation (`pos/pay.pl`)
- POS register cashup (`pos/register.pl`)
- POS refunds (`pos/register.pl`)
- All registers cashup (`pos/registers.pl`)
- Member account payouts (`members/boraccount.pl`)
- Member payment collection (`members/paycollect.pl`)

## File Modification Notes

- When updating the plugin version, use the npm scripts rather than manually editing files
- The `increment_version.js` script automatically updates both `package.json` and the main plugin file
- Template files use Template Toolkit syntax and include Koha-specific includes
- API specifications follow OpenAPI 3.0 format
- JavaScript code is embedded directly in the plugin module for staff interface injection