package Koha::Plugin::Com::OpenFifth::QZTray;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use C4::Context;
use CGI;
use Koha::DateUtils qw( dt_from_string );
use JSON qw( decode_json );
use Koha::Encryption;
use Koha::Exceptions;
use Koha::Logger;
use Koha::Cash::Registers;
use Koha::Libraries;
use Try::Tiny;

# Optional dependencies - gracefully handle missing OpenSSL modules
our $OPENSSL_AVAILABLE = 1;
eval {
    require Crypt::OpenSSL::RSA;
    require Crypt::OpenSSL::X509;
    1;
} or do {
    $OPENSSL_AVAILABLE = 0;
};

our $VERSION         = '1.1.8';
our $MINIMUM_VERSION = "22.05.00.000";

our $metadata = {
    name            => 'QZ Tray Integration',
    author          => 'OpenFifth',
    description     => 'QZ Tray printing integration for Koha',
    date_authored   => '2025-01-31',
    date_updated    => '2026-02-04',
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
};

# Definitive printer support mapping
# Maps printer name patterns to drawer control codes
# Pattern matching is case-insensitive
our $PRINTER_DRAWER_CODES = {
    # Bixolon printers
    'Bixolon SRP-350' => {
        code => 'ESC_p_0_55_y',  # chr(27).chr(112).chr(48).chr(55).chr(121)
        bytes => [27, 112, 48, 55, 121],
        description => 'Bixolon SRP-350'
    },

    # Epson printers
    'Epson TM-T88V' => {
        code => 'ESC_p_0_55_y',
        bytes => [27, 112, 48, 55, 121],
        description => 'Epson TM-T88V'
    },

    # Metapace printers
    'Metapace T' => {
        code => 'ESC_p_0_55_y',
        bytes => [27, 112, 48, 55, 121],
        description => 'Metapace T-series'
    },

    # Citizen printers (different code)
    'Citizen CBM1000' => {
        code => 'ESC_p_0_50_250',  # chr(27).chr(112).chr(0).chr(50).chr(250)
        bytes => [27, 112, 0, 50, 250],
        description => 'Citizen CBM1000'
    },
    'Citizen CBM1000 TYPE II' => {
        code => 'ESC_p_0_50_250',
        bytes => [27, 112, 0, 50, 250],
        description => 'Citizen CBM1000 Type II'
    },
    'Citizen CT-S2000' => {
        code => 'ESC_p_0_50_250',
        bytes => [27, 112, 0, 50, 250],
        description => 'Citizen CT-S2000'
    },
    'CT-S2000' => {
        code => 'ESC_p_0_50_250',
        bytes => [27, 112, 0, 50, 250],
        description => 'CT-S2000'
    },
    'Citizen CTS2000' => {
        code => 'ESC_p_0_50_250',
        bytes => [27, 112, 0, 50, 250],
        description => 'Citizen CTS2000'
    },
    'CTS2000' => {
        code => 'ESC_p_0_50_250',
        bytes => [27, 112, 0, 50, 250],
        description => 'CTS2000'
    },
};

# Default drawer code for unknown printers
our $DEFAULT_DRAWER_CODE = {
    code => 'ESC_p_0_55_y',
    bytes => [27, 112, 48, 55, 121],
    description => 'Default/Generic ESC/POS'
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    my $self = $class->SUPER::new($args);

    return $self;
}

sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    # Check for optional dependencies (affects certificate management only)
    my $dependency_check = $self->check_dependencies();
    my $openssl_available = $dependency_check->{all_available};

    # Validate encryption setup
    unless ($self->validate_encryption_setup()) {
        my $template = $self->get_template( { file => 'templates/configure.tt' } );
        $template->param(
            encryption_error => 1,
            error_message => 'Encryption is not properly configured in Koha. Please ensure encryption_key is set in koha-conf.xml.'
        );
        return $self->output_html( $template->output() );
    }

    # Migrate any existing plain text data to encrypted storage
    $self->migrate_to_encrypted_storage();

    # Handle clear printer discovery data action
    if ($cgi->param('clear_printer_discovery')) {
        $self->_clear_printer_discovery();
        print $cgi->redirect("/cgi-bin/koha/plugins/run.pl?class=" . ref($self) . "&method=configure");
        return;
    }

    unless ( $cgi->param('save') || $cgi->param('upload_certificates') || $cgi->param('save_printer_config') ) {
        my $template =
          $self->get_template( { file => 'templates/configure.tt' } );

        # Check if files exist (without decrypting for display)
        my $cert_exists = $self->retrieve_data('certificate_file') || $self->retrieve_encrypted_data('certificate_file');
        my $key_exists = $self->retrieve_data('private_key_file') || $self->retrieve_encrypted_data('private_key_file');

        # Get register mappings
        my $register_mappings = $self->retrieve_data('register_printer_mappings') || '{}';
        my $mappings_data = {};
        eval { $mappings_data = decode_json($register_mappings); };

        # Get available cash registers grouped by library
        my $current_library_id = C4::Context->userenv->{'branch'};
        my $current_register_id = C4::Context->userenv->{'register_id'} || '';

        # Get all registers for libraries the user has access to
        my $registers = Koha::Cash::Registers->search(
            { archived => 0 },
            {
                order_by => [ { '-asc' => 'branch' }, { '-asc' => 'name' } ],
                prefetch => 'branch'
            }
        );

        # Get printer discovery data (always loaded for printer settings)
        my $discovery = $self->_get_printer_discovery();

        # Group registers by library and add supported printer data
        my %registers_by_library;
        while (my $register = $registers->next) {
            my $library = $register->library;
            my $branch_code = $library->branchcode;
            my $register_id = $register->id;

            # Get discovered printers for this branch+register combination
            my $discovery_key = "${branch_code}-${register_id}";
            my $all_printers = $discovery->{$discovery_key}->{printers} || [];

            # Filter to only supported printers
            my @supported_printers;
            foreach my $printer (@$all_printers) {
                if ($self->_is_supported_printer($printer)) {
                    push @supported_printers, $printer;
                }
            }

            push @{$registers_by_library{$library->branchcode}}, {
                id => $register->id,
                name => $register->name,
                description => $register->description,
                is_current => ($register->id eq $current_register_id),
                library => $library,
                supported_printers => \@supported_printers,
                has_unsupported => (scalar(@$all_printers) > scalar(@supported_printers)),
            };
        }

        # Get upload dates and certificate expiry information
        my $cert_upload_date = $self->retrieve_data('certificate_upload_date');
        my $key_upload_date = $self->retrieve_data('private_key_upload_date');
        my $cert_expiry_date = $self->retrieve_data('certificate_expiry_date');
        my $cert_expires_soon = $self->retrieve_data('certificate_expires_soon');
        my $cert_expired = $self->retrieve_data('certificate_expired');

        # If we have a certificate but no expiry info, try to parse it now
        if ($cert_exists && !$cert_expiry_date && $openssl_available) {
            $self->_update_certificate_expiry_info();
            # Reload the data after potential update
            $cert_expiry_date = $self->retrieve_data('certificate_expiry_date');
            $cert_expires_soon = $self->retrieve_data('certificate_expires_soon');
            $cert_expired = $self->retrieve_data('certificate_expired');
        }

        # Get debug mode, discovery mode, and auto-submit settings
        my $debug_mode = $self->retrieve_data('debug_mode') || 0;
        my $discovery_mode = $self->retrieve_data('discovery_mode') || 0;
        my $auto_submit_after_drawer = $self->retrieve_data('auto_submit_after_drawer') || 0;

        # Prepare discovery display for debug mode
        my $printer_discovery_display = [];
        if ($debug_mode) {
            # Convert hash to sorted array for template display
            foreach my $key (sort keys %$discovery) {
                my $entry = $discovery->{$key};
                $entry->{key} = $key;
                $entry->{first_seen_formatted} = scalar(localtime($entry->{first_seen}));
                $entry->{last_seen_formatted} = scalar(localtime($entry->{last_seen}));
                $entry->{printer_count} = scalar(@{$entry->{printers} || []});

                # Categorize printers as supported or unsupported
                my @supported_printers;
                my @unsupported_printers;
                foreach my $printer (@{$entry->{printers} || []}) {
                    if ($self->_is_supported_printer($printer)) {
                        push @supported_printers, $printer;
                    } else {
                        push @unsupported_printers, $printer;
                    }
                }
                $entry->{supported_printers} = \@supported_printers;
                $entry->{unsupported_printers} = \@unsupported_printers;

                push @$printer_discovery_display, $entry;
            }
        }

        $template->param(
            certificate_file  => $cert_exists ? 'ENCRYPTED' : '',
            private_key_file  => $key_exists ? 'ENCRYPTED' : '',
            certificate_upload_date => $cert_upload_date,
            private_key_upload_date => $key_upload_date,
            certificate_expiry_date => $cert_expiry_date,
            certificate_expires_soon => $cert_expires_soon,
            certificate_expired => $cert_expired,
            register_mappings => $mappings_data,
            registers_by_library => \%registers_by_library,
            current_library_id => $current_library_id,
            current_register_id => $current_register_id,
            debug_mode => $debug_mode,
            discovery_mode => $discovery_mode,
            auto_submit_after_drawer => $auto_submit_after_drawer,
            printer_discovery => $printer_discovery_display,
            printer_discovery_data => $discovery,
            openssl_available => $openssl_available,
            dependency_warning => $openssl_available ? 0 : 1,
            dependency_message => $openssl_available ? '' : $dependency_check->{message},
        );

        $self->output_html( $template->output() );
    }
    else {
        my @errors;
        my $is_certificate_upload = $cgi->param('upload_certificates');
        my $is_printer_config_save = $cgi->param('save_printer_config');

        # Handle certificate file upload (for certificate upload or full save)
        my $cert_upload = $cgi->upload('certificate_upload');
        if ($cert_upload && !$is_printer_config_save) {
            if ( not defined $cert_upload ) {
                push @errors,
                  "Failed to get certificate file: " . $cgi->cgi_error;
            }
            else {
                my $cert_content;
                while ( my $line = <$cert_upload> ) {
                    $cert_content .= $line;
                }

                my $validation_result = $self->_validate_certificate($cert_content);
                if ($validation_result->{valid}) {
                    unless ($self->store_encrypted_data('certificate_file', $cert_content)) {
                        push @errors, 'Failed to securely store certificate file';
                        $self->_log_event('error', 'Certificate storage failed', {
                            error_code => 'CERT_STORAGE_FAILED',
                            action => 'certificate_upload'
                        });
                    } else {
                        # Store upload timestamp
                        $self->store_data({ certificate_upload_date => dt_from_string()->ymd() });

                        $self->_log_event('info', 'Certificate uploaded successfully', {
                            action => 'certificate_upload',
                            file_size => length($cert_content)
                        });
                    }
                } else {
                    push @errors, $validation_result->{error};
                    $self->_log_event('warn', 'Certificate validation failed', {
                        error_code => 'CERT_VALIDATION_FAILED',
                        error => $validation_result->{error},
                        action => 'certificate_upload'
                    });
                }
            }
        }

        # Handle private key file upload (for certificate upload or full save)
        my $key_upload = $cgi->upload('private_key_upload');
        if ($key_upload && !$is_printer_config_save) {
            if ( not defined $key_upload ) {
                push @errors,
                  "Failed to get private key file: " . $cgi->cgi_error;
            }
            else {
                my $key_content;
                while ( my $line = <$key_upload> ) {
                    $key_content .= $line;
                }

                my $validation_result = $self->_validate_private_key($key_content);
                if ($validation_result->{valid}) {
                    unless ($self->store_encrypted_data('private_key_file', $key_content)) {
                        push @errors, 'Failed to securely store private key file';
                        $self->_log_event('error', 'Private key storage failed', {
                            error_code => 'KEY_STORAGE_FAILED',
                            action => 'private_key_upload'
                        });
                    } else {
                        # Store upload timestamp
                        $self->store_data({ private_key_upload_date => dt_from_string()->ymd() });

                        $self->_log_event('info', 'Private key uploaded successfully', {
                            action => 'private_key_upload',
                            file_size => length($key_content)
                        });
                    }
                } else {
                    push @errors, $validation_result->{error};
                    $self->_log_event('warn', 'Private key validation failed', {
                        error_code => 'KEY_VALIDATION_FAILED',
                        error => $validation_result->{error},
                        action => 'private_key_upload'
                    });
                }
            }
        }

        # Handle register-specific printer mappings (for printer config save or full save)
        if (!$is_certificate_upload) {
            my $register_mappings = $self->retrieve_data('register_printer_mappings') || '{}';
            my $mappings_data = {};
            eval { $mappings_data = decode_json($register_mappings); };

            # Process register mappings from form (all registers allowed)
            my @register_ids = $cgi->multi_param('register_id');
            my @register_printers = $cgi->multi_param('register_printer');

            for my $i (0..$#register_ids) {
                my $register_id = $register_ids[$i] || '';
                my $register_printer = $self->_sanitize_printer_name($register_printers[$i] || '');

                # Validate register_id is numeric
                if ($register_id =~ /^\d+$/) {
                    if ($register_printer) {
                        $mappings_data->{$register_id} = $register_printer;
                    } else {
                        delete $mappings_data->{$register_id};
                    }
                }
            }

            # Handle debug mode, discovery mode, and auto-submit settings
            my $debug_mode = $cgi->param('debug_mode') ? 1 : 0;
            my $discovery_mode = $cgi->param('discovery_mode') ? 1 : 0;
            my $auto_submit_after_drawer = $cgi->param('auto_submit_after_drawer') ? 1 : 0;

            $self->store_data(
                {
                    register_printer_mappings => JSON::encode_json($mappings_data),
                    debug_mode => $debug_mode,
                    discovery_mode => $discovery_mode,
                    auto_submit_after_drawer => $auto_submit_after_drawer,
                }
            );

            # Log register printer configuration changes
            $self->_log_event('info', 'Register printer mapping updated', {
                action => 'register_printer_config_change',
                total_mappings => scalar(keys %$mappings_data)
            });
        }

        # Validate certificate and key compatibility if both are provided
        if (!@errors) {
            my $cert_file = $self->retrieve_encrypted_data('certificate_file');
            my $key_file = $self->retrieve_encrypted_data('private_key_file');
            if ($cert_file && $key_file) {
                my $compatibility_result = $self->_validate_cert_key_pair($cert_file, $key_file);
                if (!$compatibility_result->{valid}) {
                    push @errors, $compatibility_result->{error};
                    $self->_log_event('error', 'Certificate/key compatibility check failed', {
                        error_code => 'CERT_KEY_MISMATCH',
                        error => $compatibility_result->{error},
                        action => 'compatibility_validation'
                    });
                } else {
                    $self->_log_event('info', 'Certificate/key compatibility validated', {
                        action => 'compatibility_validation'
                    });
                }
            }
        }

        if (@errors) {
            my $template =
              $self->get_template( { file => 'templates/configure.tt' } );
            $template->param( errors => \@errors );
            $self->output_html( $template->output() );
        }
        else {
            if ($is_certificate_upload) {
                $self->_log_event('info', 'Certificate files uploaded successfully', {
                    action => 'certificate_upload_complete'
                });
                # Redirect back to configuration page to show results
                print $cgi->redirect("/cgi-bin/koha/plugins/run.pl?class=" . ref($self) . "&method=configure");
            } elsif ($is_printer_config_save) {
                $self->_log_event('info', 'Printer configuration updated successfully', {
                    action => 'printer_configuration_complete'
                });
                $self->go_home();
            } else {
                $self->_log_event('info', 'Plugin configuration updated successfully', {
                    action => 'configuration_complete'
                });
                $self->go_home();
            }
        }
    }
}

sub intranet_js {
    my ($self) = @_;

    # Only load QZ Tray JavaScript on pages where it's needed
    # This prevents unnecessary JavaScript loading on all other pages
    # Use SCRIPT_NAME environment variable which works under both CGI and Plack
    my $script_name = $ENV{SCRIPT_NAME} || '';

    # Get debug mode to conditionally log
    my $debug_mode = $self->retrieve_data('debug_mode') || 0;

    # List of script patterns that need QZ Tray integration
    # Using partial path matching since SCRIPT_NAME may vary
    my @supported_patterns = (
        'pos/pay.pl',
        'pos/register.pl',
        'pos/registers.pl',
        'members/boraccount.pl',
        'members/paycollect.pl',
    );

    # Check if current script matches any supported pattern
    foreach my $pattern (@supported_patterns) {
        if ($script_name =~ /\Q$pattern\E$/) {
            if ($debug_mode) {
                $self->_log_event('debug', 'Loading QZ Tray JavaScript', {
                    script_name => $script_name,
                    pattern => $pattern
                });
            }
            return $self->_generate_qz_js();
        }
    }

    # Return empty string for unsupported pages
    return '';
}

sub install {
    my ( $self, $args ) = @_;
    return 1;
}

sub upgrade {
    my ( $self, $args ) = @_;
    return 1;
}

sub uninstall {
    my ( $self, $args ) = @_;
    return 1;
}

sub api_namespace {
    my ($self) = @_;
    return 'qztray';
}

sub static_routes {
    my ( $self, $args ) = @_;
    my $spec_str = $self->mbf_read('api/staticapi.json');
    my $spec     = decode_json($spec_str);
    return $spec;
}

sub api_routes {
    my ( $self, $args ) = @_;
    my $spec_str = $self->mbf_read('api/openapi.json');
    my $spec     = decode_json($spec_str);
    return $spec;
}

sub _generate_qz_js {
    my ($self) = @_;

    # Static routes are served at /api/v1/contrib/{namespace}/static{route}
    my $static_base = "/api/v1/contrib/" . $self->api_namespace . "/static";

    # Get register mappings
    my $register_mappings = $self->retrieve_data('register_printer_mappings') || '{}';
    my $mappings_data = {};
    eval { $mappings_data = decode_json($register_mappings); };

    # Get current register ID if available
    my $current_register = C4::Context->userenv->{'register_id'} || '';

    # Get debug mode, discovery mode, and auto-submit settings
    my $debug_mode = $self->retrieve_data('debug_mode') || 0;
    my $discovery_mode = $self->retrieve_data('discovery_mode') || 0;
    my $auto_submit_after_drawer = $self->retrieve_data('auto_submit_after_drawer') || 0;

    # Properly escape JavaScript strings
    my $mappings_json = $self->_escape_js_string(JSON::encode_json($mappings_data));
    my $current_register_escaped = $self->_escape_js_string($current_register);
    my $printer_support_json = $self->_escape_js_string($self->_get_printer_support_mapping_json());

    # API routes are served at /api/v1/contrib/{namespace}{route}
    my $api_base = "/api/v1/contrib/" . $self->api_namespace;

    # Cache-busting: use query parameter instead of filename suffix
    # Plugin static files are served through Koha's REST API (Koha::REST::V1::Static)
    # which doesn't support Apache rewrite rules for version suffixes.
    # Query parameters force cache invalidation without changing the file path.
    my $cache_param = "?v=$VERSION";

    return qq{
<!-- QZ Tray JavaScript Libraries (loaded as external files) -->
<script type="text/javascript" src="$static_base/js/rsvp-3.1.0.min.js$cache_param"></script>
<script type="text/javascript" src="$static_base/js/sha-256.min.js$cache_param"></script>
<script type="text/javascript" src="$static_base/js/jsrsasign-all-min.js$cache_param"></script>
<script type="text/javascript" src="$static_base/js/qz-tray.js$cache_param"></script>

<script type="text/javascript">
// QZ Tray Configuration
window.qzConfig = {
    apiBase: '$api_base',
    registerMappings: JSON.parse('$mappings_json'),
    currentRegister: '$current_register_escaped',
    debugMode: $debug_mode,
    discoveryMode: $discovery_mode,
    autoSubmitAfterDrawer: $auto_submit_after_drawer,
    printerSupport: JSON.parse('$printer_support_json')
};
</script>

<!-- QZ Tray Integration Modules (loaded in dependency order) -->
<script type="text/javascript" src="$static_base/js/qz-transaction-lock.js$cache_param"></script>
<script type="text/javascript" src="$static_base/js/qz-config.js$cache_param"></script>
<script type="text/javascript" src="$static_base/js/qz-messaging.js$cache_param"></script>
<script type="text/javascript" src="$static_base/js/qz-auth.js$cache_param"></script>
<script type="text/javascript" src="$static_base/js/qz-availability.js$cache_param"></script>
<script type="text/javascript" src="$static_base/js/qz-drawer.js$cache_param"></script>
<script type="text/javascript" src="$static_base/js/qz-page-detector.js$cache_param"></script>
<script type="text/javascript" src="$static_base/js/qz-button-manager.js$cache_param"></script>
<script type="text/javascript" src="$static_base/js/qz-pos-toolbar.js$cache_param"></script>
<script type="text/javascript" src="$static_base/js/qz-tray-integration.js$cache_param"></script>
    };
}

sub _read_js_file {
    my ( $self, $file_path ) = @_;

    # Use mbf_read to read file from plugin bundle
    my $content = $self->mbf_read($file_path);

    if ($content) {

        # Clean up the content to avoid JavaScript syntax issues
        $content =~ s/\r\n/\n/g;       # Normalize line endings
        $content =~ s/\r/\n/g;         # Convert remaining CR to LF
        $content = $content . "\n";    # Ensure ends with newline

        return $content;
    }

    return "// File not found via mbf_read: $file_path";
}

sub _escape_js_content {
    my ( $self, $content ) = @_;

    # Convert any non-ASCII characters to JavaScript Unicode escape sequences
    # This handles any Unicode character that might cause syntax errors
    $content =~ s/([^\x00-\x7F])/sprintf("\\u%04X", ord($1))/ge;

    return $content;
}

# Validation helper methods for security improvements

sub _validate_certificate {
    my ($self, $cert_content) = @_;

    # Check if OpenSSL modules are available
    unless ($OPENSSL_AVAILABLE) {
        return { valid => 0, error => 'OpenSSL libraries not available for certificate validation' };
    }

    # Basic validation
    return { valid => 0, error => 'Certificate file appears to be empty' }
        unless $cert_content && length($cert_content) > 0;

    # Check file size (reasonable limit: 10KB)
    return { valid => 0, error => 'Certificate file is too large (max 10KB)' }
        if length($cert_content) > 10240;

    # Check for PEM format markers
    unless ($cert_content =~ /-----BEGIN CERTIFICATE-----/ &&
            $cert_content =~ /-----END CERTIFICATE-----/) {
        return { valid => 0, error => 'Certificate must be in PEM format' };
    }

    # Attempt to parse the certificate and extract expiry
    my $expiry_info = {};
    eval {
        my $x509 = Crypt::OpenSSL::X509->new_from_string($cert_content);
        # Basic parsing validation - certificate can be loaded

        # Extract expiry date
        my $not_after = $x509->notAfter();
        if ($not_after) {
            $expiry_info = $self->_parse_certificate_expiry($not_after);
        }
    };

    if ($@) {
        return { valid => 0, error => 'Invalid certificate format or corrupted file' };
    }

    # Store expiry information if available
    if ($expiry_info->{expiry_date}) {
        $self->store_data({
            certificate_expiry_date => $expiry_info->{expiry_date},
            certificate_expires_soon => $expiry_info->{expires_soon},
            certificate_expired => $expiry_info->{expired}
        });
    }

    return { valid => 1 };
}

sub _validate_private_key {
    my ($self, $key_content) = @_;

    # Check if OpenSSL modules are available
    unless ($OPENSSL_AVAILABLE) {
        return { valid => 0, error => 'OpenSSL libraries not available for private key validation' };
    }

    # Basic validation
    return { valid => 0, error => 'Private key file appears to be empty' }
        unless $key_content && length($key_content) > 0;

    # Check file size (reasonable limit: 10KB)
    return { valid => 0, error => 'Private key file is too large (max 10KB)' }
        if length($key_content) > 10240;

    # Check for PEM format markers (support both RSA and generic private key formats)
    unless (($key_content =~ /-----BEGIN RSA PRIVATE KEY-----/ &&
             $key_content =~ /-----END RSA PRIVATE KEY-----/) ||
            ($key_content =~ /-----BEGIN PRIVATE KEY-----/ &&
             $key_content =~ /-----END PRIVATE KEY-----/)) {
        return { valid => 0, error => 'Private key must be in PEM format' };
    }

    # Attempt to parse the private key
    eval {
        my $rsa = Crypt::OpenSSL::RSA->new_private_key($key_content);
        # Basic validation - ensure it's a valid RSA key
        my $key_size = $rsa->size();
        return { valid => 0, error => 'Private key is too small (minimum 2048 bits)' }
            if $key_size < 256; # 256 bytes = 2048 bits
    };

    if ($@) {
        return { valid => 0, error => 'Invalid private key format or corrupted file' };
    }

    return { valid => 1 };
}

sub _validate_cert_key_pair {
    my ($self, $cert_content, $key_content) = @_;

    # Check if OpenSSL modules are available
    unless ($OPENSSL_AVAILABLE) {
        return { valid => 0, error => 'OpenSSL libraries not available for certificate/key validation' };
    }

    eval {
        # Parse certificate and private key
        my $x509 = Crypt::OpenSSL::X509->new_from_string($cert_content);
        my $rsa = Crypt::OpenSSL::RSA->new_private_key($key_content);

        # Extract public key from certificate
        my $cert_pubkey = $x509->pubkey();

        # This is a simplified check - in production you might want more robust validation
        # For now, we verify both can be parsed without errors
    };

    if ($@) {
        return { valid => 0, error => 'Certificate and private key do not appear to be compatible' };
    }

    return { valid => 1 };
}

sub _sanitize_printer_name {
    my ($self, $printer_name) = @_;

    return '' unless defined $printer_name;

    # Remove any potentially dangerous characters
    $printer_name =~ s/[<>&"']//g;  # Remove HTML/JS dangerous chars
    $printer_name =~ s/[\x00-\x1F\x7F]//g;  # Remove control characters

    # Limit length to reasonable size
    $printer_name = substr($printer_name, 0, 255) if length($printer_name) > 255;

    return $printer_name;
}

sub _escape_js_string {
    my ($self, $string) = @_;

    return '' unless defined $string;

    # Comprehensive JavaScript string escaping
    $string =~ s/\\/\\\\/g;      # Backslash
    $string =~ s/'/\\'/g;        # Single quote
    $string =~ s/"/\\"/g;        # Double quote
    $string =~ s/\n/\\n/g;       # Newline
    $string =~ s/\r/\\r/g;       # Carriage return
    $string =~ s/\t/\\t/g;       # Tab
    $string =~ s/\f/\\f/g;       # Form feed
    $string =~ s/\x08/\\b/g;     # Backspace (use \x08, not \b which is word boundary)
    $string =~ s/\//\\\//g;      # Forward slash (optional but safer)

    # Escape Unicode control characters and non-printable characters
    $string =~ s/([\x00-\x1F\x7F-\x9F])/sprintf("\\u%04X", ord($1))/ge;

    return $string;
}

sub _parse_certificate_expiry {
    my ($self, $not_after_string) = @_;

    return {} unless $not_after_string;

    my $result = {};

    # Parse OpenSSL date format: "Dec 31 23:59:59 2025 GMT"
    if ($not_after_string =~ /^(\w{3})\s+(\d{1,2})\s+(\d{2}):(\d{2}):(\d{2})\s+(\d{4})\s+GMT$/) {
        my ($month_str, $day, $hour, $min, $sec, $year) = ($1, $2, $3, $4, $5, $6);

        # Convert month name to number
        my %months = (
            'Jan' => 1, 'Feb' => 2, 'Mar' => 3, 'Apr' => 4,
            'May' => 5, 'Jun' => 6, 'Jul' => 7, 'Aug' => 8,
            'Sep' => 9, 'Oct' => 10, 'Nov' => 11, 'Dec' => 12
        );

        my $month = $months{$month_str};
        if ($month) {
            my $expiry_date = sprintf('%04d-%02d-%02d', $year, $month, $day);
            $result->{expiry_date} = $expiry_date;

            # Calculate if certificate expires soon (within 30 days) or has expired
            my $expiry_dt = dt_from_string("$expiry_date 23:59:59");
            my $now_dt = dt_from_string();
            my $warning_dt = $now_dt->clone->add(days => 30);

            $result->{expired} = $expiry_dt < $now_dt ? 1 : 0;
            $result->{expires_soon} = (!$result->{expired} && $expiry_dt < $warning_dt) ? 1 : 0;
        }
    }

    return $result;
}

sub _update_certificate_expiry_info {
    my ($self) = @_;

    return unless $OPENSSL_AVAILABLE;

    my $cert_content = $self->retrieve_encrypted_data('certificate_file');
    return unless $cert_content;

    eval {
        my $x509 = Crypt::OpenSSL::X509->new_from_string($cert_content);
        my $not_after = $x509->notAfter();

        if ($not_after) {
            my $expiry_info = $self->_parse_certificate_expiry($not_after);
            if ($expiry_info->{expiry_date}) {
                $self->store_data({
                    certificate_expiry_date => $expiry_info->{expiry_date},
                    certificate_expires_soon => $expiry_info->{expires_soon},
                    certificate_expired => $expiry_info->{expired}
                });
            }
        }
    };

    if ($@) {
        $self->_log_event('warn', 'Failed to update certificate expiry info', {
            error => "$@",
            action => 'update_certificate_expiry_info'
        });
    }
}


# Dependency checking methods

=head3 check_dependencies

Check if all required dependencies are available

=cut

sub check_dependencies {
    my ($self) = @_;

    my @missing = ();
    my $message = '';

    # Check OpenSSL dependencies
    unless ($OPENSSL_AVAILABLE) {
        push @missing, 'libcrypt-openssl-x509-perl';
    }

    if (@missing) {
        $message = 'The following server-side dependencies are missing and must be installed before this plugin can function properly: ' . join(', ', @missing) . '. ';
        $message .= 'Please contact your system administrator to install these packages. ';
        $message .= 'On Debian/Ubuntu systems, run: sudo apt install ' . join(' ', @missing);

        return {
            all_available => 0,
            missing => \@missing,
            message => $message
        };
    }

    return {
        all_available => 1,
        missing => [],
        message => 'All dependencies are available'
    };
}

# Logging and error handling methods

=head3 _get_logger

Get a logger instance for this plugin

=cut

sub _get_logger {
    my ($self) = @_;
    return Koha::Logger->get({ interface => 'api', category => 'plugin.qztray' });
}

=head3 _log_event

Log an event with structured data

    $self->_log_event('info', 'Configuration updated', {
        user => $patron_id,
        action => 'certificate_upload'
    });

=cut

sub _log_event {
    my ($self, $level, $message, $data) = @_;

    my $logger = $self->_get_logger();
    $data ||= {};

    # Add plugin context
    $data->{plugin} = 'QZTray';
    $data->{version} = $VERSION;

    # Add user context if available
    if (C4::Context->userenv) {
        $data->{user_id} = C4::Context->userenv->{number};
        $data->{user_cardnumber} = C4::Context->userenv->{cardnumber};
    }

    my $structured_message = "$message: " . JSON::encode_json($data);

    if ($level eq 'error') {
        $logger->error($structured_message);
    } elsif ($level eq 'warn') {
        $logger->warn($structured_message);
    } elsif ($level eq 'debug') {
        $logger->debug($structured_message);
    } else {
        $logger->info($structured_message);
    }
}

# Secure storage methods following Koha best practices

=head3 store_encrypted_data

Store sensitive data encrypted in the plugin data table

    $self->store_encrypted_data($key, $sensitive_value);

=cut

sub store_encrypted_data {
    my ($self, $key, $value) = @_;

    return unless defined $value;

    try {
        my $cipher = Koha::Encryption->new;
        my $encrypted = $cipher->encrypt_hex($value);
        $self->store_data({ $key => $encrypted });
        return 1;
    } catch {
        $self->_log_event('error', 'Failed to encrypt plugin data', {
            key => $key,
            error => "$_",
            action => 'store_encrypted_data'
        });
        return 0;
    };
}

=head3 retrieve_encrypted_data

Retrieve and decrypt sensitive data from plugin data table

    my $decrypted_value = $self->retrieve_encrypted_data($key);

=cut

sub retrieve_encrypted_data {
    my ($self, $key) = @_;

    my $encrypted = $self->retrieve_data($key);
    return unless $encrypted;

    # Check if data looks like encrypted hex (for backwards compatibility)
    return $encrypted unless $encrypted =~ /^[0-9a-fA-F]+$/;

    try {
        my $cipher = Koha::Encryption->new;
        return $cipher->decrypt_hex($encrypted);
    } catch {
        $self->_log_event('error', 'Failed to decrypt plugin data', {
            key => $key,
            error => "$_",
            action => 'retrieve_encrypted_data'
        });
        return;
    };
}

=head3 validate_encryption_setup

Check if encryption is properly configured

    return 1 if $self->validate_encryption_setup();

=cut

sub validate_encryption_setup {
    my ($self) = @_;

    try {
        Koha::Encryption->new;
        return 1;
    } catch {
        if ($_->isa('Koha::Exceptions::MissingParameter')) {
            $self->_log_event('warn', 'Encryption not configured', {
                error => $_->message,
                action => 'validate_encryption_setup'
            });
        } else {
            $self->_log_event('error', 'Encryption validation failed', {
                error => "$_",
                action => 'validate_encryption_setup'
            });
        }
        return 0;
    };
}

=head3 migrate_to_encrypted_storage

Migrate existing plain text secrets to encrypted storage

=cut

sub migrate_to_encrypted_storage {
    my ($self) = @_;

    # List of keys that should be encrypted
    my @sensitive_keys = qw(certificate_file private_key_file);

    for my $key (@sensitive_keys) {
        my $plain_value = $self->retrieve_data($key);

        # If it exists and doesn't look like hex (encrypted), migrate it
        if ($plain_value && $plain_value !~ /^[0-9a-fA-F]+$/) {
            if ($self->store_encrypted_data($key, $plain_value)) {
                $self->_log_event('info', 'Migrated data to encrypted storage', {
                    key => $key,
                    action => 'migration'
                });
            } else {
                $self->_log_event('error', 'Failed to migrate data to encrypted storage', {
                    key => $key,
                    action => 'migration'
                });
            }
        }
    }
}

=head3 _log_printer_discovery

Log discovered printers for a branch+register combination (only when debug mode is enabled)

    $self->_log_printer_discovery({
        branch_code => 'MAIN',
        branch_name => 'Main Library',
        register_id => '1',
        register_name => 'Register 1',
        printers => ['Epson TM-T88V', 'HP LaserJet'],
        page_url => '/pos/pay.pl'
    });

Stores data as a hash keyed by "branch_code-register_id" with unique printer lists.

=cut

sub _log_printer_discovery {
    my ($self, $discovery_data) = @_;

    return unless $discovery_data && ref($discovery_data) eq 'HASH';

    # Retrieve existing printer discovery data
    my $printer_discovery_json = $self->retrieve_data('printer_discovery') || '{}';
    my $printer_discovery = {};
    eval { $printer_discovery = decode_json($printer_discovery_json); };

    # If decode failed, start fresh
    $printer_discovery = {} unless ref($printer_discovery) eq 'HASH';

    # Create key for this branch+register combination
    my $branch_code = $discovery_data->{branch_code} || 'unknown';
    my $register_id = $discovery_data->{register_id} || 'none';
    my $key = "${branch_code}-${register_id}";

    # Get or create entry for this key
    my $entry = $printer_discovery->{$key} || {
        branch_code => $branch_code,
        branch_name => $discovery_data->{branch_name} || $branch_code,
        register_id => $register_id ne 'none' ? $register_id : '',
        register_name => $discovery_data->{register_name} || '',
        printers => [],
        first_seen => time(),
        last_seen => time()
    };

    # Update metadata
    $entry->{branch_name} = $discovery_data->{branch_name} if $discovery_data->{branch_name};
    $entry->{register_name} = $discovery_data->{register_name} if $discovery_data->{register_name};
    $entry->{last_seen} = time();

    # Merge new printers with existing ones (keep unique)
    my %seen_printers = map { $_ => 1 } @{$entry->{printers} || []};
    foreach my $printer (@{$discovery_data->{printers} || []}) {
        next if $seen_printers{$printer};
        push @{$entry->{printers}}, $printer;
        $seen_printers{$printer} = 1;
    }

    # Store updated entry
    $printer_discovery->{$key} = $entry;

    # Store updated discovery data
    $self->store_data({
        printer_discovery => JSON::encode_json($printer_discovery)
    });

    # Also log to Koha log for permanent record
    $self->_log_event('debug', 'Printer discovery logged', {
        key => $key,
        branch_code => $branch_code,
        register_id => $register_id,
        printer_count => scalar(@{$entry->{printers}}),
        action => 'printer_discovery_debug'
    });
}

=head3 _get_printer_discovery

Retrieve printer discovery data for display in configuration UI

    my $discovery = $self->_get_printer_discovery();

Returns hash reference of discovery data keyed by "branch_code-register_id".

=cut

sub _get_printer_discovery {
    my ($self) = @_;

    my $printer_discovery_json = $self->retrieve_data('printer_discovery') || '{}';
    my $printer_discovery = {};
    eval { $printer_discovery = decode_json($printer_discovery_json); };

    # If decode failed, return empty hash
    $printer_discovery = {} unless ref($printer_discovery) eq 'HASH';

    return $printer_discovery;
}

=head3 _clear_printer_discovery

Clear all printer discovery data

    $self->_clear_printer_discovery();

=cut

sub _clear_printer_discovery {
    my ($self) = @_;

    $self->store_data({
        printer_discovery => '{}'
    });

    $self->_log_event('info', 'Printer discovery data cleared', {
        action => 'clear_printer_discovery'
    });
}

=head3 _get_printer_drawer_code

Get the drawer control code for a printer (case-insensitive matching)

    my $drawer_code_info = $self->_get_printer_drawer_code($printer_name);
    # Returns: { code => 'ESC_p_0_55_y', bytes => [27, 112, 48, 55, 121], description => '...' }
    # Returns undef if printer not supported

=cut

sub _get_printer_drawer_code {
    my ($self, $printer_name) = @_;

    return unless defined $printer_name && length($printer_name) > 0;

    # Case-insensitive matching against supported printer patterns
    my $printer_lower = lc($printer_name);

    foreach my $pattern (keys %$PRINTER_DRAWER_CODES) {
        my $pattern_lower = lc($pattern);
        if (index($printer_lower, $pattern_lower) != -1) {
            return $PRINTER_DRAWER_CODES->{$pattern};
        }
    }

    return; # Not supported
}

=head3 _is_supported_printer

Check if a printer is supported (case-insensitive matching)

    my $is_supported = $self->_is_supported_printer($printer_name);

Returns true if the printer has a specific drawer code defined, false otherwise.

=cut

sub _is_supported_printer {
    my ($self, $printer_name) = @_;

    return 0 unless defined $printer_name && length($printer_name) > 0;

    # Use the drawer code lookup - if we get a code, it's supported
    return defined $self->_get_printer_drawer_code($printer_name);
}

=head3 _get_supported_printer_patterns

Get list of all supported printer patterns

    my @patterns = $self->_get_supported_printer_patterns();

Returns array of printer name patterns that are supported.

=cut

sub _get_supported_printer_patterns {
    my ($self) = @_;
    return sort keys %$PRINTER_DRAWER_CODES;
}

=head3 _get_printer_support_mapping_json

Get the printer support mapping as JSON for JavaScript

    my $json = $self->_get_printer_support_mapping_json();

Returns JSON string with printer patterns and their drawer codes.

=cut

sub _get_printer_support_mapping_json {
    my ($self) = @_;

    # Convert the mapping to a JavaScript-friendly format
    my %js_mapping;
    foreach my $pattern (keys %$PRINTER_DRAWER_CODES) {
        my $code_info = $PRINTER_DRAWER_CODES->{$pattern};
        $js_mapping{$pattern} = {
            bytes => $code_info->{bytes},
            description => $code_info->{description}
        };
    }

    # Add default code
    $js_mapping{'_default'} = {
        bytes => $DEFAULT_DRAWER_CODE->{bytes},
        description => $DEFAULT_DRAWER_CODE->{description}
    };

    return JSON::encode_json(\%js_mapping);
}


1;
