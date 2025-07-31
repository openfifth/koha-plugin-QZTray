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
    
    # Read JavaScript files and inline them
    my $rsvp_js = $self->_read_js_file('js/dependencies/rsvp-3.1.0.min.js');
    my $sha256_js = $self->_read_js_file('js/dependencies/sha-256.min.js');
    my $qz_js = $self->_read_js_file('js/qz-tray.js');
    
    # Debug: Log file sizes to help identify issues
    warn "RSVP JS length: " . length($rsvp_js);
    warn "SHA256 JS length: " . length($sha256_js);
    warn "QZ JS length: " . length($qz_js);
    
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
    
    // QZ Tray Main Library
    $qz_js
    
    // Initialize QZ Tray if available
    if (typeof initQZTray === 'function') {
        initQZTray();
    }
})();
</script>
    };
}

sub _read_js_file {
    my ( $self, $file_path ) = @_;
    
    my $full_path = $self->mbf_path($file_path);
    
    if ( -f $full_path ) {
        open my $fh, '<:encoding(UTF-8)', $full_path or return "// Error reading $file_path";
        local $/;
        my $content = <$fh>;
        close $fh;
        
        # Clean up the content to avoid JavaScript syntax issues
        $content =~ s/\r\n/\n/g;  # Normalize line endings
        $content =~ s/\r/\n/g;    # Convert remaining CR to LF
        $content = $content . "\n"; # Ensure ends with newline
        
        return $content;
    }
    
    return "// File not found: $file_path";
}

1;
