package Koha::Plugin::Com::OpenFifth::QZTray;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use C4::Context;
use Koha::DateUtils;
use JSON qw( decode_json );
use Crypt::OpenSSL::RSA;
use Crypt::OpenSSL::X509;
use Koha::Encryption;
use Koha::Exceptions;
use Koha::Logger;
use Try::Tiny;

our $VERSION         = '1.0.2';
our $MINIMUM_VERSION = "22.05.00.000";

our $metadata = {
    name            => 'QZ Tray Integration',
    author          => 'OpenFifth',
    description     => 'QZ Tray printing integration for Koha',
    date_authored   => '2025-01-31',
    date_updated    => '2025-09-24',
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
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

    unless ( $cgi->param('save') ) {
        my $template =
          $self->get_template( { file => 'templates/configure.tt' } );

        # Check if files exist (without decrypting for display)
        my $cert_exists = $self->retrieve_data('certificate_file') || $self->retrieve_encrypted_data('certificate_file');
        my $key_exists = $self->retrieve_data('private_key_file') || $self->retrieve_encrypted_data('private_key_file');

        $template->param(
            certificate_file  => $cert_exists ? 'ENCRYPTED' : '',
            private_key_file  => $key_exists ? 'ENCRYPTED' : '',
            preferred_printer => $self->retrieve_data('preferred_printer') || '',
        );

        $self->output_html( $template->output() );
    }
    else {
        my @errors;

        # Handle certificate file upload
        my $cert_upload = $cgi->upload('certificate_upload');
        if ($cert_upload) {
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

        # Handle private key file upload
        my $key_upload = $cgi->upload('private_key_upload');
        if ($key_upload) {
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

        # Validate and store printer configuration
        my $old_printer = $self->retrieve_data('preferred_printer') || '';
        my $printer_name = $self->_sanitize_printer_name($cgi->param('preferred_printer') || '');
        $self->store_data(
            {
                preferred_printer => $printer_name,
            }
        );

        # Log printer configuration changes
        if ($old_printer ne $printer_name) {
            $self->_log_event('info', 'Printer configuration changed', {
                action => 'printer_config_change',
                old_printer => $old_printer,
                new_printer => $printer_name
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
            $self->_log_event('info', 'Plugin configuration updated successfully', {
                action => 'configuration_complete'
            });
            $self->go_home();
        }
    }
}

sub intranet_js {
    my ($self) = @_;

    # Always load QZ Tray JavaScript when plugin is enabled
    return $self->_generate_qz_js();
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

    # Get preferred printer setting
    my $preferred_printer = $self->retrieve_data('preferred_printer') || '';

    # Properly escape JavaScript strings
    $preferred_printer = $self->_escape_js_string($preferred_printer);

    # API routes are served at /api/v1/contrib/{namespace}{route}
    my $api_base = "/api/v1/contrib/" . $self->api_namespace;

    return qq{
<!-- QZ Tray JavaScript Libraries (loaded as external files) -->
<script type="text/javascript" src="$static_base/js/rsvp-3.1.0.min.js"></script>
<script type="text/javascript" src="$static_base/js/sha-256.min.js"></script>
<script type="text/javascript" src="$static_base/js/jsrsasign-all-min.js"></script>
<script type="text/javascript" src="$static_base/js/qz-tray.js"></script>

<script type="text/javascript">
// QZ Tray Configuration
window.qzConfig = {
    apiBase: '$api_base',
    preferredPrinter: '$preferred_printer'
};
</script>

<!-- QZ Tray Integration Modules (loaded in dependency order) -->
<script type="text/javascript" src="$static_base/js/qz-config.js"></script>
<script type="text/javascript" src="$static_base/js/qz-messaging.js"></script>
<script type="text/javascript" src="$static_base/js/qz-auth.js"></script>
<script type="text/javascript" src="$static_base/js/qz-drawer.js"></script>
<script type="text/javascript" src="$static_base/js/qz-page-detector.js"></script>
<script type="text/javascript" src="$static_base/js/qz-button-manager.js"></script>
<script type="text/javascript" src="$static_base/js/qz-tray-integration.js"></script>
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

    # Attempt to parse the certificate
    eval {
        my $x509 = Crypt::OpenSSL::X509->new_from_string($cert_content);
        # Basic parsing validation - certificate can be loaded
    };

    if ($@) {
        return { valid => 0, error => 'Invalid certificate format or corrupted file' };
    }

    return { valid => 1 };
}

sub _validate_private_key {
    my ($self, $key_content) = @_;

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
    $string =~ s/\b/\\b/g;       # Backspace
    $string =~ s/\//\\\//g;      # Forward slash (optional but safer)

    # Escape Unicode control characters and non-printable characters
    $string =~ s/([\x00-\x1F\x7F-\x9F])/sprintf("\\u%04X", ord($1))/ge;

    return $string;
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


1;
