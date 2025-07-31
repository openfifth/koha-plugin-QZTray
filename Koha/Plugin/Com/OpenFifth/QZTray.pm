package Koha::Plugin::Com::OpenFifth::QZTray;

use Modern::Perl;

use base qw(Koha::Plugins::Base);

use C4::Context;
use Koha::DateUtils;

our $VERSION = '1.0.0';
our $MINIMUM_VERSION = "22.05.00.000";

our $metadata = {
    name            => 'QZ Tray Integration',
    author          => 'OpenFifth',
    description     => 'QZ Tray printing integration for Koha',
    date_authored   => '2025-01-31',
    date_updated    => '2025-01-31',
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

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template( { file => 'templates/configure.tt' } );

        $template->param(
            certificate_file => $self->retrieve_data('certificate_file') || '',
            private_key_file => $self->retrieve_data('private_key_file') || '',
            enable_staff     => $self->retrieve_data('enable_staff') || 0,
            enable_opac      => $self->retrieve_data('enable_opac') || 0,
        );

        $self->output_html( $template->output() );
    } else {
        my @errors;

        # Handle certificate file upload
        my $cert_upload = $cgi->upload('certificate_upload');
        if ( $cert_upload ) {
            if ( not defined $cert_upload ) {
                push @errors, "Failed to get certificate file: " . $cgi->cgi_error;
            } else {
                my $cert_content;
                while ( my $line = <$cert_upload> ) {
                    $cert_content .= $line;
                }
                if ( $cert_content ) {
                    $self->store_data({ certificate_file => $cert_content });
                } else {
                    push @errors, "Certificate file appears to be empty";
                }
            }
        }

        # Handle private key file upload
        my $key_upload = $cgi->upload('private_key_upload');
        if ( $key_upload ) {
            if ( not defined $key_upload ) {
                push @errors, "Failed to get private key file: " . $cgi->cgi_error;
            } else {
                my $key_content;
                while ( my $line = <$key_upload> ) {
                    $key_content .= $line;
                }
                if ( $key_content ) {
                    $self->store_data({ private_key_file => $key_content });
                } else {
                    push @errors, "Private key file appears to be empty";
                }
            }
        }

        # Store other configuration
        $self->store_data({
            enable_staff => $cgi->param('enable_staff') || 0,
            enable_opac  => $cgi->param('enable_opac') || 0,
        });

        if ( @errors ) {
            my $template = $self->get_template( { file => 'templates/configure.tt' } );
            $template->param( errors => \@errors );
            $self->output_html( $template->output() );
        } else {
            $self->go_home();
        }
    }
}

sub intranet_js {
    my ( $self ) = @_;
    
    return '' unless $self->retrieve_data('enable_staff');
    
    my $certificate = $self->retrieve_data('certificate_file') || '';
    my $private_key = $self->retrieve_data('private_key_file') || '';
    
    return '' unless ( $certificate && $private_key );
    
    return $self->_generate_qz_js( $certificate, $private_key );
}

sub opac_js {
    my ( $self ) = @_;
    
    return '' unless $self->retrieve_data('enable_opac');
    
    my $certificate = $self->retrieve_data('certificate_file') || '';
    my $private_key = $self->retrieve_data('private_key_file') || '';
    
    return '' unless ( $certificate && $private_key );
    
    return $self->_generate_qz_js( $certificate, $private_key );
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



sub _generate_qz_js {
    my ( $self, $certificate, $private_key ) = @_;
    
    # Read JavaScript files directly with mbf_read
    my $rsvp_js = $self->mbf_read('js/dependencies/rsvp-3.1.0.min.js') // "// RSVP not found";
    my $sha256_js = $self->mbf_read('js/dependencies/sha-256.min.js.orig') // "// SHA-256 not found";
    my $jsrsasign_js = $self->mbf_read('js/dependencies/jsrsasign-all-min.js') // "// JSRSASign not found";
    my $qz_js = $self->mbf_read('js/qz-tray.js') // "// QZ Tray not found";
    
    # Debug: Check file sizes
    warn "JSRSASign JS length: " . length($jsrsasign_js);
    warn "JSRSASign JS starts with: " . substr($jsrsasign_js, 0, 100) if length($jsrsasign_js) > 0;
    
    
    # Escape JavaScript strings
    $certificate =~ s/\\/\\\\/g;
    $certificate =~ s/'/\\'/g;
    $certificate =~ s/\n/\\n/g;
    
    $private_key =~ s/\\/\\\\/g;
    $private_key =~ s/'/\\'/g;
    $private_key =~ s/\n/\\n/g;
    
    return qq{
<script type="text/javascript">
// QZ Tray Configuration
window.qzConfig = {
    certificate: '$certificate',
    privateKey: '$private_key'
};

// Inline QZ Tray dependencies and main library
(function() {
    // RSVP Library
    $rsvp_js
    
    // SHA-256 Library  
    $sha256_js
    
    // JSRSASign Library (for KEYUTIL and signing)
    $jsrsasign_js
    
    // QZ Tray Main Library
    $qz_js
})();

// QZ Tray Cash Drawer Functionality (global scope)
function displayError(err) {
    console.error(err);
}

function chr(i) {
    return String.fromCharCode(i);
}

function drawerCode(printer) {
    var code = [chr(27) + chr(112) + chr(48) + chr(55) + chr(121)]; //default code
    if (printer.indexOf('Bixolon SRP-350') !== -1 ||
        printer.indexOf('Epson TM-T88V') !== -1 ||
        printer.indexOf('Metapace T') !== -1 ) {
        code = [chr(27) + chr(112) + chr(48) + chr(55) + chr(121)];
    }
    if (printer.indexOf('Citizen CBM1000') !== -1) {
        code = [chr(27) + chr(112) + chr(0) + chr(50) + chr(250)];
    }
    return code;
}

function popDrawer(b) {
        qz.security.setCertificatePromise(function(resolve, reject) {
            resolve(window.qzConfig.certificate);
        });
        
        qz.security.setSignaturePromise(function(toSign) {
            return function(resolve, reject) {
                try {
                    if (typeof KEYUTIL === 'undefined') {
                        console.error('KEYUTIL not available, using empty signature for testing');
                        resolve('');
                        return;
                    }
                    var pk = KEYUTIL.getKey(window.qzConfig.privateKey);
                    var sig = new KJUR.crypto.Signature({"alg": "SHA1withRSA"});
                    sig.init(pk);
                    sig.updateString(toSign);
                    var hex = sig.sign();
                    resolve(stob64(hextorstr(hex)));
                } catch (err) {
                    console.error('Signing error:', err);
                    reject(err);
                }
            };
        });
        
        qz.websocket.connect().then(function () {
            console.log('QZ Tray connected!');
            return qz.printers.getDefault()
        }).then(function (printer) {
            var config = qz.configs.create(printer);
            var data = drawerCode(printer);
            console.log('Opening drawer for printer:', printer);
            return qz.print(config, data);
        }).then(function() {
            \$("#drawer-button").hide();
            if (b) \$(b).show();
        }).catch(displayError);
}

// Wait for DOM to be ready
\$(document).ready(function() {
    // Debug: Check if signing libraries are loaded
    console.log('KEYUTIL available:', typeof KEYUTIL !== 'undefined');
    console.log('KJUR available:', typeof KJUR !== 'undefined');
    console.log('RSAKey available:', typeof RSAKey !== 'undefined');
    console.log('Sha256 available:', typeof Sha256 !== 'undefined');
    console.log('CryptoJS available:', typeof CryptoJS !== 'undefined');
    
    // Only add drawer button on main page for testing
    if (window.location.href.indexOf('mainpage.pl') !== -1) {
        console.log('QZ Tray: Adding test drawer button to mainpage');
        // Add a test button to the main content area
        \$('#main_intranet-main').prepend('<div style="margin: 10px 0;"><input type="button" class="btn btn-primary" id="drawer-button" value="Test Cash Drawer" onclick="popDrawer();return false;" /></div>');
    }
});
</script>
    };
}

sub _read_js_file {
    my ( $self, $file_path ) = @_;
    
    # Use mbf_read to read file from plugin bundle
    my $content = $self->mbf_read($file_path);
    
    if ( $content ) {
        # Clean up the content to avoid JavaScript syntax issues
        $content =~ s/\r\n/\n/g;  # Normalize line endings
        $content =~ s/\r/\n/g;    # Convert remaining CR to LF
        $content = $content . "\n"; # Ensure ends with newline
        
        return $content;
    }
    
    return "// File not found via mbf_read: $file_path";
}

1;
