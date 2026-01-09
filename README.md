# QZ Tray Integration Plugin for Koha

A Koha plugin that integrates QZ Tray printing functionality for automatic cash drawer opening and receipt printing operations.

## Features

- **Cash Drawer Integration**: Automatically open cash drawers during payment transactions
- **Quick Drawer Access**: One-click button on POS page to open cash drawer without processing a transaction
- **Register-Specific Printer Configuration**: Map specific printers to individual cash registers
- **Multi-Library Support**: Configure printers across multiple library branches
- **Secure Certificate Management**: Encrypted storage of QZ Tray security certificates
- **Smart Printer Selection**: Uses form-selected register or falls back to system default
- **Visual Configuration Interface**: Library-grouped register display with current session highlighting

## Requirements

### Server-Side Dependencies

The plugin requires OpenSSL cryptographic libraries for secure certificate handling:

```bash
# On Debian/Ubuntu systems:
sudo apt update
sudo apt install libcrypt-openssl-x509-perl
```

### Client-Side Requirements

- **QZ Tray** installed on client workstations
- Modern web browser with JavaScript enabled
- Network connectivity between Koha server and client machines

### Koha Requirements

- Koha 22.05 or later
- Cash management permissions enabled
- At least one cash register configured per library

## Installation

1. **Install server dependencies**:

   ```bash
   sudo apt install libcrypt-openssl-x509-perl
   ```

2. **Download the plugin**:
   - Download the latest `.kpz` file from the releases page

3. **Install in Koha**:
   - Navigate to Administration → Plugins
   - Click "Upload plugin"
   - Select the downloaded `.kpz` file
   - Click "Upload"

4. **Configure the plugin**:
   - Click "Configure" next to the QZ Tray Integration plugin
   - Upload your QZ Tray security certificate and private key files
   - Configure printer mappings for your cash registers

## Configuration

### 1. Security Certificates

QZ Tray requires security certificates for secure communication:

1. Generate certificates using QZ Tray's certificate generator
2. Upload the certificate file (`.crt` or `.pem`)
3. Upload the private key file (`.key` or `.pem`)

### 2. Printer Configuration

Configure printers for each cash register:

1. **By Library**: Registers are grouped by library branch for easy organization
2. **Current Session Indicator**: Your active register is highlighted in green
3. **Printer Selection**: Choose specific printers or use system default
4. **Refresh Printer List**: Detect available printers on the network

### 3. Permissions

Ensure users have appropriate cash management permissions:

- `cash_management` → `takepayment` for payment operations
- `cash_management` → `cashup` for register management
- `cash_management` → `anonymous_refund` for refund operations

## Usage

Once configured, the plugin automatically:

1. **Detects Payment Pages**: Integrates with POS payment forms
2. **Selects Appropriate Printer**: Uses register-specific or default printer
3. **Opens Cash Drawer**: Sends drawer open commands during transactions
4. **Handles Errors**: Displays user-friendly error messages

### Quick Drawer Access

On the Point of Sale page, a toolbar with an "Open cash drawer" button appears above the page heading. This allows staff to open the register for:

- Making change without processing a transaction
- Accessing physical cash for non-sale purposes
- Testing drawer functionality

The button is disabled until QZ Tray initializes, then becomes active with visual feedback during operation.

### Supported Pages

- **Point of Sale** (pos/pay.pl): Quick access button plus automatic drawer opening on payment confirmation
- Register cashup operations
- Member account payments
- Refund transactions

### Supported Printers

The plugin includes optimized drawer control codes for:

- **Bixolon SRP-350 series**
- **Epson TM-T88V**
- **Metapace T-series**
- **Citizen CBM1000**
- **Citizen CT-S2000** (all name variations)
- Other ESC/POS compatible printers (using default codes)

**Note for Citizen CT-S2000**: If your printer driver settings force drawer opening on every print, consider setting up two printer instances:

- One for receipts (driver set to "Never" open drawer)
- One for drawer control (Generic/Text Only driver) configured in this plugin

## Troubleshooting

### Common Issues

**"QZ Tray not connected"**

- Ensure QZ Tray is running on the client machine
- Check network connectivity
- Verify browser allows unsigned applets (if using development certificates)

**"Printer not found"**

- Click "Refresh Printer List" to detect available printers
- Verify printer is powered on and connected
- Check printer network configuration

**"Certificate errors"**

- Ensure certificate and private key match
- Verify files are in PEM format
- Check that encryption is configured in Koha

### Debug Information

Enable debug logging in Koha to see detailed QZ Tray communication logs:

- Check the `plugin.qztray` log category
- Monitor JavaScript console for client-side errors

## Development

### File Structure

```
Koha/Plugin/Com/OpenFifth/QZTray/
├── QZTray.pm                    # Main plugin file
├── templates/
│   └── configure.tt             # Configuration template
├── js/
│   ├── qz-config.js            # Configuration management
│   ├── qz-drawer.js            # Cash drawer operations
│   ├── qz-messaging.js         # User messaging
│   ├── qz-auth.js              # Authentication handling
│   ├── qz-button-manager.js    # UI button replacement
│   ├── qz-page-detector.js     # Page detection logic
│   ├── qz-pos-toolbar.js       # POS toolbar with quick access button
│   └── qz-tray-integration.js  # Main integration
├── api/
│   ├── openapi.json            # API specification
│   └── staticapi.json          # Static route specification
└── Controllers/
    └── Auth.pm                 # Authentication controller
```

## Support

For issues and bug reports, please use the project's issue tracker.

## License

This plugin is released under the GNU General Public License v3.0, consistent with Koha's licensing.

## Version History

- **v1.1.1**: Performance optimization - JavaScript now loads only on required pages instead of system-wide; fixed FOUC (flash of unstyled content) by removing split initialization
- **v1.1.0**: Added quick cash drawer open button to POS page toolbar; wrapped console.log statements in debug mode checks
- **v1.0.12**: Rearranged configuration page for better UX
- **v1.0.11**: Added configurable debug mode for console logging; improved configuration UI with sticky toolbar and updated button styling
- **v1.0.10**: Critical fix for JavaScript string escaping bug; added comprehensive debug logging for printer selection
- **v1.0.8**: Fixed invalid CSS selector in printer list refresh functionality
- **v1.0.7**: Added support for Citizen CT-S2000 printer with optimized drawer control codes
- **v1.0.4**: Enhanced register-library grouping and session highlighting
- **v1.0.3**: Improved form-based register detection
- **v1.0.2**: Added register-specific printer mappings
- **v1.0.1**: Security and error handling improvements
- **v1.0.0**: Initial release with basic QZ Tray integration

